import cloud/tui
import cloud/web
import gleam/erlang/process
import howdy
import howdy/ui/live

pub fn main() -> Nil {
  // let assert Ok(registry) = sessions.start()
  let assert Ok(tui) = live.start(tui.app(), with: Nil)

  let assert Ok(_) =
    howdy.new()
    |> howdy.bind(to: "127.0.0.1")
    |> howdy.controller(web.controller(tui))
    |> howdy.start
  process.sleep_forever()
}
