//// The web interface, a page with the terminal interface on it.
//// Each connection runs its own terminal interface on the server, the page only draws it and sends keys.

import cloud/apex/context.{type Context}
import cloud/apex/tui
import howdy/controller
import howdy/ui/live
import howdy/ui/page
import lustre/element/html

pub fn page(ctx: controller.Context) {
  page.new("EYG cloud")
  |> page.live
  |> page.head([html.style([], "body { margin: 0; background: #181818; }")])
  |> page.body([live.mount("/tui")])
  |> page.respond(ctx)
}

/// The terminal interface of a connection, the page mounts it.
pub fn tui(ctx: controller.Context, context: Context) {
  live.serve(ctx, tui.app(), with: context)
}
