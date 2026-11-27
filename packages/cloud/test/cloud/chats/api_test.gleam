import cloud/apex/context.{Context}
import cloud/helpers.{dispatch}
import cloud/server
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import howdy/testing as simulate

fn field(response, name, decoder) {
  let assert Ok(value) =
    json.parse(simulate.text(response), decode.at([name], decoder))
  value
}

fn box(context, name) {
  let response =
    simulate.request(http.Post, "/boxes")
    |> simulate.json_body(json.object([#("name", json.string(name))]))
    |> dispatch(context)
  field(response, "id", decode.string)
}

pub fn chat_with_a_configured_llm_test() {
  use context <- helpers.context()
  let server = server.start(process.new_subject())
  let context =
    Context(..context, llms: dict.from_list([#("test", server.llm(server))]))
  let response = dispatch(simulate.request(http.Get, "/llms"), context)
  assert "[\"test\"]" == simulate.text(response)

  let home = box(context, "home")
  let start = fn(llm) {
    simulate.request(http.Post, "/boxes/" <> home <> "/chats")
    |> simulate.json_body(json.object([#("llm", json.string(llm))]))
    |> dispatch(context)
  }
  assert 422 == start("other").status
  let response = start("test")
  assert 201 == response.status
  let id = field(response, "id", decode.string)

  let response =
    simulate.request(http.Post, "/chats/" <> id <> "/messages")
    |> simulate.json_body(json.object([#("message", json.string("hi"))]))
    |> dispatch(context)
  assert "hi #1" == field(response, "reply", decode.string)

  let response = dispatch(simulate.request(http.Get, "/chats/" <> id), context)
  assert "test" == field(response, "llm", decode.string)
  let roles = decode.at(["role"], decode.string)
  assert ["user", "assistant"]
    == field(response, "messages", decode.list(roles))
  let response =
    dispatch(simulate.request(http.Get, "/boxes/" <> home <> "/chats"), context)
  assert [id] == field_list(response)
  let response =
    dispatch(simulate.request(http.Get, "/chats/" <> id <> "/events"), context)
  assert 2
    == list.length(string.split(string.trim(simulate.text(response)), "\n"))
}

fn field_list(response) {
  let assert Ok(ids) =
    json.parse(
      simulate.text(response),
      decode.list(decode.at(["id"], decode.string)),
    )
  ids
}

pub fn run_tool_calls_from_an_agent_test() {
  // The calls run at the same time, which one connection cannot.
  let context = helpers.pool_context()
  let home = box(context, helpers.unique("agent"))
  let call = fn(id, code) {
    json.object([
      #("id", json.string(id)),
      #("type", json.string("function")),
      #(
        "function",
        json.object([
          #("name", json.string("run")),
          #(
            "arguments",
            json.string(
              json.to_string(json.object([#("code", json.string(code))])),
            ),
          ),
        ]),
      ),
    ])
  }
  let response =
    simulate.request(http.Post, "/boxes/" <> home <> "/calls")
    |> simulate.json_body(
      json.object([
        #(
          "tool_calls",
          json.preprocessed_array([
            call("a", "!int_add(1, 2)"),
            call("b", "!int_add(1, \"two\")"),
            call("c", "perform Nope({})"),
          ]),
        ),
      ]),
    )
    |> dispatch(context)
  assert 200 == response.status
  let message = {
    use id <- decode.field("tool_call_id", decode.string)
    use content <- decode.field("content", decode.string)
    use error <- decode.field("error", decode.bool)
    use shell <- decode.field("shell", decode.optional(decode.string))
    decode.success(#(id, content, error, shell))
  }
  let assert Ok([a, b, c]) =
    json.parse(simulate.text(response), decode.list(message))
  assert #("a", False) == #(a.0, a.2)
  assert string.contains(a.1, "3")
  assert #("b", True) == #(b.0, b.2)
  assert #("c", True) == #(c.0, c.2)
  // Each call ran in a shell of its own in the box.
  let assert Some(shell) = a.3
  let response =
    dispatch(simulate.request(http.Get, "/shells/" <> shell), context)
  assert home == field(response, "box", decode.string)
  assert a.3 != b.3

  let response =
    simulate.request(http.Post, "/boxes/" <> home <> "/calls")
    |> simulate.json_body(json.object([#("tool_calls", json.string("no"))]))
    |> dispatch(context)
  assert 400 == response.status
}
