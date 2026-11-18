//// The web interface, a page with the terminal interface on it.
//// Each connection runs its own terminal interface on the server, the page only draws it and sends keys.
//// Requests need the password if there is one, see `access`.

import cloud/apex/access.{type Access}
import cloud/apex/context.{type Context}
import cloud/apex/terminal
import cloud/apex/tui
import gleam/http/request
import gleam/http/response
import howdy
import howdy/controller
import howdy/ui/live
import howdy/ui/page
import lustre/attribute
import lustre/element/html

pub fn start(context: Context, access: Access, port: Int) {
  howdy.new()
  |> howdy.bind(to: access.bind(access))
  |> howdy.listening(on: port)
  |> howdy.middleware(fn(ctx: controller.Context, next) {
    case
      access.allowed(access, request.get_header(ctx.request, "authorization"))
    {
      True -> next(ctx)
      False ->
        controller.status(ctx, 401)
        |> response.set_header(access.challenge.0, access.challenge.1)
    }
  })
  |> howdy.controller(controller(context))
  |> howdy.start
}

pub fn controller(context: Context) -> controller.Controller {
  controller.new("/")
  |> controller.get("/", fn(ctx) {
    page.new("EYG cloud")
    |> page.live
    |> page.head([html.style([], "body { margin: 0; background: #181818; }")])
    |> page.body([html.script([attribute.type_("module")], terminal.script)])
    |> page.body([live.mount("/tui")])
    |> page.respond(ctx)
  })
  |> controller.get("/tui", fn(ctx) {
    live.serve(ctx, tui.app(), with: context)
  })
  |> controller.build
}
