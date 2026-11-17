//// The web interface, a page with the terminal interface on it.
//// Each connection runs its own terminal interface on the server, the page only draws it and sends keys.
//// There is no authentication yet so only local connections are accepted.

import cloud/apex/context.{type Context}
import cloud/apex/tui
import howdy
import howdy/controller
import howdy/ui/live
import howdy/ui/page
import lustre/element/html

pub fn start(context: Context, port: Int) {
  howdy.new()
  |> howdy.bind(to: "127.0.0.1")
  |> howdy.listening(on: port)
  |> howdy.controller(controller(context))
  |> howdy.start
}

pub fn controller(context: Context) -> controller.Controller {
  controller.new("/")
  |> controller.get("/", fn(ctx) {
    page.new("EYG cloud")
    |> page.live
    |> page.head([html.style([], "body { margin: 0; background: #181818; }")])
    |> page.body([live.mount("/tui")])
    |> page.respond(ctx)
  })
  |> controller.get("/tui", fn(ctx) {
    live.serve(ctx, tui.app(), with: context)
  })
  |> controller.build
}
