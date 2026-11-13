//// The cloud's HTTP server, built with howdy.
////
//// | Request | Response |
//// | --- | --- |
//// | `GET /` | Service status |
//// | `GET /login`, `POST /login` | Sign in by name, the first person is the admin |
//// | `GET /shell` | The web shell, a live view at `/live/shell` |
//// | `POST /api/<Operation>` | Perform a configuration API operation with the person's shell policy |
//// | `GET /artifacts` | A list of artifacts |
//// | `GET /artifacts/<name>/<path>` | A file from the latest version, `index.html` for an empty path |
//// | `GET /artifacts/<name>/v/<version>/<path>` | A file from a version |
//// | `/connections/<name>/webhook[/<path>]`, any method | A request to a listening chat adapter |
////
//// Artifact files are served with a sandbox content security policy,
//// so scripts in a bundle run in an opaque origin without network access.

import cloud/artifacts
import cloud/beam/execute
import cloud/operation
import cloud/registry
import cloud/users.{type User}
import cloud/web/json_value
import cloud/web/runner
import cloud/web/shell
import cloud/webhook
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/cookie
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import howdy
import howdy/content.{type Content}
import howdy/controller.{type Context as Request}
import howdy/ui/live
import howdy/ui/page

pub type Context {
  Context(
    artifacts: Subject(artifacts.Message),
    /// Answer a request to the webhook of a connection.
    webhook: fn(String, webhook.Request) -> Result(webhook.Response, String),
    /// The web shell and API, not available without a registry.
    web: Option(runner.Context),
  )
}

/// The largest request body accepted, webhook deliveries are at most 25MB.
const max_body = 26_214_400

const session_cookie = "eyg_session"

pub fn start(port: Int, context: Context) {
  app(context)
  |> howdy.bind(to: "0.0.0.0")
  |> howdy.listening(on: port)
  |> howdy.start
}

pub fn app(context: Context) -> howdy.App {
  let routes =
    controller.new("/")
    |> controller.get("/", fn(_) { text(200, "EYG cloud") })
    |> controller.get("/artifacts", fn(_) { index(context.artifacts) })
    |> controller.get("/artifacts/:name/v/:version/*path", fn(ctx) {
      let name = param(ctx, "name")
      case int.parse(param(ctx, "version")) {
        Ok(version) ->
          serve(context.artifacts, name, Some(version), param(ctx, "path"))
        Error(Nil) -> text(404, "not found")
      }
    })
    |> controller.get("/artifacts/:name/*path", fn(ctx) {
      serve(context.artifacts, param(ctx, "name"), None, param(ctx, "path"))
    })
    |> controller.get("/artifacts/:name", fn(ctx) {
      serve(context.artifacts, param(ctx, "name"), None, "")
    })
    |> webhook_routes("/connections/:name/webhook", context)
    |> webhook_routes("/connections/:name/webhook/*path", context)
    |> controller.get("/login", fn(ctx) { login_page(ctx, next(ctx), "") })
    |> controller.post("/login", fn(ctx) { with_web(context, sign_in(ctx, _)) })
    |> controller.get("/shell", fn(ctx) {
      with_user(context, ctx, fn(_web, _user) { shell_page(ctx) })
    })
    |> controller.get("/live/shell", fn(ctx) {
      with_user(context, ctx, fn(web, user) {
        let shells = process.call(web.registry, 5000, registry.Shells)
        let query = request.get_query(ctx.request) |> result.unwrap([])
        let code = list.key_find(query, "code") |> result.unwrap("")
        let bind = case
          list.key_find(query, "workspace"),
          list.key_find(query, "channel")
        {
          Ok(workspace), Ok(channel) -> Some(runner.Binding(workspace, channel))
          _, _ -> None
        }
        let args = shell.Args(web, user, shells, code, bind)
        live.serve(ctx, shell.app(), with: args)
      })
    })
    |> controller.get("/api/me", fn(ctx) {
      with_api_user(context, ctx, fn(_web, user) {
        json.object([
          #("name", json.string(user.name)),
          #("admin", json.bool(user.admin)),
          #("shell", json.string(user.shell)),
        ])
        |> controller.json(ctx, _)
      })
    })
    |> controller.post("/api/:operation", fn(ctx) {
      with_api_user(context, ctx, fn(web, user) {
        api(ctx, web, user, param(ctx, "operation"))
      })
    })
    |> controller.build
  howdy.new() |> howdy.controller(routes)
}

fn param(ctx: Request, name) {
  controller.param(ctx, name)
  |> result.unwrap("")
  |> uri.percent_decode
  |> result.unwrap("")
}

fn with_web(context: Context, then) {
  case context.web {
    Some(web) -> then(web)
    None -> text(404, "not found")
  }
}

/// The signed in person, from the session cookie.
fn user(web: runner.Context, ctx: Request) -> Result(User, Nil) {
  use token <- result.try(
    request.get_cookies(ctx.request) |> list.key_find(session_cookie),
  )
  process.call(web.registry, 5000, registry.UserByToken(token, _))
}

/// Pages send people who have not signed in to the sign in page.
fn with_user(context: Context, ctx: Request, then) {
  use web <- with_web(context)
  case user(web, ctx) {
    Ok(user) -> then(web, user)
    Error(Nil) -> {
      let here = case ctx.request.query {
        Some(query) -> ctx.request.path <> "?" <> query
        None -> ctx.request.path
      }
      redirect("/login?next=" <> uri.percent_encode(here))
    }
  }
}

fn with_api_user(context: Context, ctx: Request, then) {
  use web <- with_web(context)
  case user(web, ctx) {
    Ok(user) -> then(web, user)
    Error(Nil) -> text(401, "sign in at /login")
  }
}

/// Where to go after signing in, only paths on this server.
fn next(ctx: Request) {
  case request.get_query(ctx.request) |> result.try(list.key_find(_, "next")) {
    Ok("/" <> _ as next) -> next
    _ -> "/shell"
  }
}

fn sign_in(ctx: Request, web: runner.Context) {
  let form =
    controller.read_body(ctx, limit: 100_000)
    |> result.replace_error(Nil)
    |> result.try(bit_array.to_string)
    |> result.try(uri.parse_query)
    |> result.unwrap([])
  let name = list.key_find(form, "name") |> result.unwrap("")
  let next = case list.key_find(form, "next") {
    Ok("/" <> _ as next) -> next
    _ -> "/shell"
  }
  case process.call(web.registry, 5000, registry.SignIn(name, _)) {
    Ok(user) ->
      redirect(next)
      |> response.set_cookie(
        session_cookie,
        user.token,
        cookie.Attributes(
          ..cookie.defaults(http.Http),
          max_age: Some(31_536_000),
        ),
      )
    Error(reason) ->
      login_page(ctx, next, reason) |> controller.with_status(400)
  }
}

/// Perform an operation by running `perform <Operation>(input)` with the person's shell policy,
/// so the HTTP API is gated exactly as the shells are.
fn api(ctx: Request, web: runner.Context, user: User, label: String) {
  case operation.spec(label) {
    Error(Nil) -> text(404, "no operation named " <> label)
    Ok(_) -> {
      let input = case controller.read_body(ctx, limit: 1_000_000) {
        Ok(<<>>) | Error(_) -> Ok(v.unit())
        Ok(body) ->
          bit_array.to_string(body)
          |> result.replace_error(Nil)
          |> result.try(fn(body) {
            json.parse(body, json_value.decoder()) |> result.replace_error(Nil)
          })
      }
      case input {
        Error(Nil) -> text(400, "the body must be JSON")
        Ok(input) -> {
          let code = "perform " <> label <> "(input)"
          let #(execute.Run(result:, ..), _) =
            runner.run(web, user, None, code, [#("input", input)])
          case result {
            Ok(Some(value)) -> controller.json(ctx, json_value.to_json(value))
            Ok(None) -> controller.json(ctx, json.null())
            Error(reason) ->
              controller.json(
                ctx,
                json.object([#("error", json.string(reason))]),
              )
              |> controller.with_status(403)
          }
        }
      }
    }
  }
}

/// Every method is accepted, a webhook connection decides what each one means.
fn webhook_routes(routes, path, context) {
  let handle = fn(ctx) {
    webhook(ctx, param(ctx, "name"), "/" <> param(ctx, "path"), context)
  }
  routes
  |> controller.get(path, handle)
  |> controller.post(path, handle)
  |> controller.put(path, handle)
  |> controller.patch(path, handle)
  |> controller.delete(path, handle)
}

fn webhook(ctx: Request, name: String, path: String, context: Context) {
  case controller.read_body(ctx, limit: max_body) {
    Error(_) -> text(413, "body too large")
    Ok(body) ->
      case bit_array.to_string(body) {
        Error(Nil) -> text(400, "body is not utf8")
        Ok(body) -> {
          let query =
            request.get_query(ctx.request)
            |> result.unwrap([])
          let delivery =
            webhook.Request(
              method: ctx.request.method,
              path:,
              headers: ctx.request.headers,
              query:,
              body:,
            )
          case context.webhook(name, delivery) {
            Ok(webhook.Response(status:, body:)) -> text(status, body)
            Error(reason) -> text(404, reason)
          }
        }
      }
  }
}

fn serve(store, name, version, path) {
  case artifacts.call(store, artifacts.Get(name, version, _)) {
    Error(reason) -> text(404, reason)
    Ok(#(_version, bundle)) ->
      case artifacts.file(bundle, path) {
        Error(Nil) -> text(404, "not found")
        Ok(file) ->
          response.new(200)
          |> response.set_header("content-type", file.media_type)
          |> response.set_header(
            "content-security-policy",
            "sandbox allow-scripts; default-src 'self' 'unsafe-inline' data:",
          )
          |> response.set_body(
            content.Bytes(bytes_tree.from_bit_array(file.content)),
          )
      }
  }
}

fn index(store) {
  let rows =
    artifacts.call(store, artifacts.List)
    |> list.map(fn(entry) {
      let #(name, artifact) = entry
      let href = "/artifacts/" <> uri.percent_encode(name) <> "/"
      let sharing = case artifact.shared {
        True -> "shared"
        False -> "private"
      }
      "<li><a href=\""
      <> href
      <> "\">"
      <> escape(name)
      <> "</a> by #"
      <> escape(artifact.owner.name)
      <> ", "
      <> int.to_string(list.length(artifact.versions))
      <> " versions, "
      <> sharing
      <> "</li>"
    })
    |> string.concat
  html(
    "<!doctype html><title>Artifacts</title><style>body{font-family:sans-serif;margin:2em}</style><h1>Artifacts</h1><ul>"
    <> rows
    <> "</ul>",
  )
}

fn login_page(ctx: Request, next: String, error: String) {
  let error = case error {
    "" -> ""
    error -> "<p class=error>" <> escape(error) <> "</p>"
  }
  controller.html(
    ctx,
    "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'><title>Sign in</title>
<style>body{font:16px/1.5 -apple-system,sans-serif;background:#1e1e2e;color:#cdd6f4;display:grid;place-items:center;min-height:100vh;margin:0}
form{background:#181825;padding:32px;border-radius:12px;display:grid;gap:12px;width:min(360px,90vw)}
input,button{font:inherit;padding:10px;border-radius:8px;border:1px solid #45475a;background:#11111b;color:#cdd6f4}
button{background:#89b4fa;color:#11111b;border:0;font-weight:600}.error{color:#f38ba8}p{margin:0;color:#a6adc8}</style>
<form method=post action=/login><h1>EYG cloud</h1><p>The first person to sign in to a new cloud is its admin, with every effect. Everyone after chooses a shell from cloud.eyg.</p><p>This example signs people in by name only, run it behind your own authentication.</p>"
      <> error
      <> "<input type=hidden name=next value=\""
      <> escape(next) |> string.replace("\"", "&quot;")
      <> "\"><input name=name placeholder='Your name' autofocus><button>Sign in</button></form>",
  )
}

/// The query, code and a channel to bind to, is passed on to the live view.
fn shell_page(ctx: Request) {
  let route = case ctx.request.query {
    Some(query) -> "/live/shell?" <> query
    None -> "/live/shell"
  }
  page.new("EYG shell")
  |> page.live
  |> page.body([live.mount(route)])
  |> page.respond(ctx)
}

fn escape(text) {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}

fn html(body) -> Response(Content) {
  response.new(200)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(content.Text(body))
}

fn text(status, body) -> Response(Content) {
  response.new(status)
  |> response.set_header("content-type", "text/plain; charset=utf-8")
  |> response.set_body(content.Text(body))
}

fn redirect(to) -> Response(Content) {
  response.new(303)
  |> response.set_header("location", to)
  |> response.set_body(content.Empty)
}
