import cloud/sessions
import cloud/web
import gleam/erlang/process
import howdy

pub fn main() -> Nil {
  // The block store belongs to this process, which lives as long as the app.
  let assert Ok(registry) = sessions.start()
  let assert Ok(_) =
    howdy.new()
    |> howdy.bind(to: "127.0.0.1")
    |> howdy.controller(web.controller(registry))
    |> howdy.start
  process.sleep_forever()
}
