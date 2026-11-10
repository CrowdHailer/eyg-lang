import howdy/controller
import howdy/ui
import howdy/ui/live
import howdy/ui/page
import lustre/element/html as h

pub fn controller(tui) -> controller.Controller {
  controller.new("/")
  |> controller.get("/", list_users)
  |> controller.get("/tui", fn(ctx) { live.serve_shared(ctx, tui) })
  |> controller.build
}

fn list_users(ctx: controller.Context) {
  page.new("Orders")
  |> page.live
  |> page.body([
    ui.container([], [
      ui.h1("Orders"),
      ui.p([h.text("Nothing here yet.")]),
    ]),
    live.mount("/tui"),
  ])
  |> page.respond(ctx)
}
