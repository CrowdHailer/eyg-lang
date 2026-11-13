//// A minimal chat app: channels, messages, threads and reactions.
////
//// It exists to show how a chat platform plugs into EYG cloud,
//// see `guides/cloud/channel_plugins.md`. State is kept in memory.
////
//// ```sh
//// PORT=8080 gleam run
//// ```

import envoy
import example_chat/server
import example_chat/store
import gleam/erlang/application
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/result
import howdy
import simplifile

pub fn main() -> Nil {
  let port = envoy.get("PORT") |> result.try(int.parse) |> result.unwrap(8080)
  let assert Ok(store) =
    store.start([
      "general",
      "random",
      "links",
      "dev",
      "social",
      "news",
      "founders",
    ])
  let assert Ok(priv) = application.priv_directory("example_chat")
  let assert Ok(styles) = simplifile.read(priv <> "/chat.css")
  let assert Ok(_) =
    server.app(store, styles)
    |> howdy.bind("0.0.0.0")
    |> howdy.listening(port)
    |> howdy.start
  io.println("Chat running at http://localhost:" <> int.to_string(port))
  process.sleep_forever()
}
