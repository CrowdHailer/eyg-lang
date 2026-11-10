import cloud/counter
import cloud/web
import gleam/erlang/process
import howdy
import howdy/ui/live

pub fn main() -> Nil {
  // let assert Ok(registry) = sessions.start()
  let assert Ok(counter) = live.start(counter.app(), with: 0)

  let assert Ok(_) =
    howdy.new()
    |> howdy.bind(to: "127.0.0.1")
    |> howdy.controller(web.controller(counter))
    |> howdy.start
  process.sleep_forever()
}
