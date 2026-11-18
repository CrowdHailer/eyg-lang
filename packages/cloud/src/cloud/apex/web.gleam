//// The web interface, a page with the terminal interface on it.
//// Each connection runs its own terminal interface on the server, the page only draws it and sends keys.
//// Requests need the password if there is one, see `access`.
////
//// Artifacts are files of a box read by the root of the box's files, `/artifacts/:root/*path`.
//// They are written by sessions and so are not trusted. Each is a sandbox with its own origin,
//// its scripts run but cannot read the site, and requests from another origin, such as a sandbox, are refused.

import cloud/apex/access.{type Access}
import cloud/apex/context.{type Context}
import cloud/apex/terminal
import cloud/apex/tui
import cloud/artifacts
import gleam/bytes_tree
import gleam/http/request
import gleam/http/response
import gleam/result
import gleam/string
import howdy
import howdy/content
import howdy/controller
import howdy/ui/live
import howdy/ui/page
import lustre/attribute
import lustre/element/html
import multiformats/cid/v1

pub fn start(context: Context, access: Access, port: Int) {
  app(context, access)
  |> howdy.bind(to: access.bind(access))
  |> howdy.listening(on: port)
  |> howdy.start
}

pub fn app(context: Context, access: Access) -> howdy.App {
  howdy.new()
  |> howdy.middleware(fn(ctx: controller.Context, next) {
    let allowed =
      access.allowed(access, request.get_header(ctx.request, "authorization"))
    case allowed, same_origin(ctx.request) {
      True, True -> next(ctx)
      True, False -> controller.status(ctx, 403)
      False, _ ->
        controller.status(ctx, 401)
        |> response.set_header(access.challenge.0, access.challenge.1)
    }
  })
  |> howdy.controller(controller(context))
}

// A request with an origin, such as the terminal's socket, comes from a page of this site.
// A page in a sandbox has the origin `null`.
fn same_origin(request) {
  case request.get_header(request, "origin") {
    Error(Nil) -> True
    Ok(origin) ->
      case string.split_once(origin, "://") {
        Ok(#(_, host)) -> Ok(host) == request.get_header(request, "host")
        Error(Nil) -> False
      }
  }
}

pub fn controller(context: Context) -> controller.Controller {
  controller.new("/")
  |> controller.get("/", fn(ctx) {
    page.new("EYG cloud")
    |> page.live
    // Phones do not enlarge the text of the terminal, so it fits the cells measured for it.
    |> page.head([
      html.style(
        [],
        "html { -webkit-text-size-adjust: 100%; text-size-adjust: 100%; } body { margin: 0; background: #181818; }",
      ),
    ])
    |> page.body([html.script([attribute.type_("module")], terminal.script)])
    |> page.body([live.mount("/tui")])
    |> page.respond(ctx)
  })
  |> controller.get("/tui", fn(ctx) {
    live.serve(ctx, tui.app(), with: context)
  })
  |> controller.get("/artifacts/:root/*path", fn(ctx) {
    let file = {
      use root <- result.try(controller.param(ctx, "root"))
      use path <- result.try(controller.param(ctx, "path"))
      use #(root, _) <- result.try(
        v1.from_string(root) |> result.replace_error(Nil),
      )
      use bytes <- result.map(artifacts.read(root, path, context.state))
      #(path, bytes)
    }
    case file {
      Ok(#(path, bytes)) ->
        response.new(200)
        |> response.set_body(content.Bytes(bytes_tree.from_bit_array(bytes)))
        |> response.set_header("content-type", artifacts.content_type(path))
        |> response.set_header(
          "content-security-policy",
          "sandbox allow-scripts",
        )
        |> response.set_header("x-content-type-options", "nosniff")
        // A root never changes.
        |> response.set_header(
          "cache-control",
          "private, max-age=31536000, immutable",
        )
      Error(Nil) -> controller.status(ctx, 404)
    }
  })
  |> controller.build
}
