//// The cloud's HTTP server, it serves artifacts.
////
//// | Request | Response |
//// | --- | --- |
//// | `GET /` | A list of artifacts |
//// | `GET /artifacts/<name>/<path>` | A file from the latest version, `index.html` for an empty path |
//// | `GET /artifacts/<name>/v/<version>/<path>` | A file from a version |
////
//// Artifact files are served with a sandbox content security policy,
//// so scripts in a bundle run in an opaque origin without network access.

import cloud/artifacts
import cloud/connections/github
import gleam/bit_array
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri
import howdy
import howdy/content.{type Content}
import howdy/controller.{type Context as Request}

pub type Context {
  Context(
    artifacts: Subject(artifacts.Message),
    webhook: fn(github.Delivery) -> Result(Nil, String),
  )
}

const max_body = 26_214_400

pub fn start(port: Int, context: Context) {
  app(context)
  |> howdy.bind(to: "0.0.0.0")
  |> howdy.listening(on: port)
  |> howdy.start
}

pub fn app(context: Context) -> howdy.App {
  let store = context.artifacts
  let routes =
    controller.new("/")
    |> controller.get("/", fn(_) { index(store) })
    |> controller.get("/artifacts", fn(_) { index(store) })
    |> controller.get("/artifacts/:name/v/:version/*path", fn(ctx) {
      case int.parse(param(ctx, "version")) {
        Ok(version) ->
          serve(store, param(ctx, "name"), Some(version), param(ctx, "path"))
        Error(Nil) -> text(404, "not found")
      }
    })
    |> controller.get("/artifacts/:name/*path", fn(ctx) {
      serve(store, param(ctx, "name"), None, param(ctx, "path"))
    })
    |> controller.get("/artifacts/:name", fn(ctx) {
      serve(store, param(ctx, "name"), None, "")
    })
    |> controller.post("/connections/:name/webhook", fn(ctx) {
      webhook(ctx, param(ctx, "name"), context)
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
  |> response.set_body(content.Text(body))
}

fn webhook(ctx: Request, name: String, context: Context) {
  let header = fn(key) {
    request.get_header(ctx.request, key) |> result.unwrap("")
  }
  case controller.read_body(ctx, limit: max_body) {
    Error(_) -> text(413, "body too large")
    Ok(body) ->
      case bit_array.to_string(body) {
        Error(Nil) -> text(400, "body is not utf8")
        Ok(body) -> {
          let delivery =
            github.Delivery(
              connection: name,
              kind: header("x-github-event"),
              delivery: header("x-github-delivery"),
              signature: header("x-hub-signature-256"),
              body:,
            )
          case context.webhook(delivery) {
            Ok(Nil) -> text(202, "accepted")
            Error(reason) -> text(400, reason)
          }
        }
      }
  }
}
