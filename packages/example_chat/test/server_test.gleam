import example_chat/server
import example_chat/store
import gleam/dynamic/decode
import gleam/json
import howdy/testing

pub fn howdy_routes_preserve_the_channel_plugin_api_test() {
  let assert Ok(store) = store.start(["general"])
  let app = server.app(store, "")
  let author =
    json.object([
      #("id", json.string("u1")),
      #("name", json.string("alice")),
      #("bot", json.bool(False)),
    ])
  let message =
    json.object([
      #("channel", json.string("C1")),
      #("thread", json.null()),
      #("author", author),
      #("text", json.string("hello")),
    ])
  let response = testing.post("/api/messages", message) |> testing.send(app)
  assert response.status == 200
  assert testing.json(
      response,
      decode.field("text", decode.string, decode.success),
    )
    == Ok("hello")
  let reaction =
    json.object([
      #("message", json.string("m1")),
      #("emoji", json.string("books")),
      #("author", author),
    ])
  let response = testing.post("/api/reactions", reaction) |> testing.send(app)
  assert response.status == 200
  let response = testing.get("/api/events?after=1") |> testing.send(app)
  assert testing.json(
      response,
      decode.list(decode.field("type", decode.string, decode.success)),
    )
    == Ok(["reacted"])
  let response = testing.get("/api/messages?channel=C1") |> testing.send(app)
  assert testing.json(
      response,
      decode.list(decode.field("text", decode.string, decode.success)),
    )
    == Ok(["hello"])
  let response =
    testing.post("/api/messages", json.object([])) |> testing.send(app)
  assert response.status == 400
}
