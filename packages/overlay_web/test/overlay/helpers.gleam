import castor
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import javascript/mutable_reference
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama
import overlay/llm/tool
import overlay/web/state

pub fn new_reader(items, tail) {
  let ref = mutable_reference.new(#(items, tail))

  fn() {
    let #(items, tail) = mutable_reference.get(ref)
    case items {
      [item, ..rest] -> {
        mutable_reference.set(ref, #(rest, tail))
        Ok(Some(item))
      }
      [] ->
        case tail {
          Ok(Nil) -> Ok(None)
          Error(reason) -> Error(reason)
        }
    }
    |> promise.resolve()
  }
}

pub fn ollama_messages_decoder() {
  use messages <- decode.field(
    "messages",
    decode.list({
      use role <- decode.field("role", decode.string)
      use content <- decode.field("content", decode.string)
      decode.success(#(role, content))
    }),
  )
  decode.success(messages)
}

pub fn ollama_tools_decoder() {
  use messages <- decode.field(
    "tools",
    decode.list({
      use function <- decode.field("function", {
        use name <- decode.field("name", decode.string)
        use description <- decode.field("description", decode.string)
        use parameters <- decode.field("parameters", castor.decoder())
        case parameters {
          castor.Object(properties:, required:, ..) -> {
            let parameters =
              properties
              |> dict.to_list
              |> list.map(fn(property) {
                let #(key, spec) = property
                #(key, spec, list.contains(required, key))
              })
            decode.success(tool.Tool(name:, description:, parameters:))
          }
          _ ->
            decode.failure(
              tool.Tool(name: "", description: "", parameters: []),
              "tool",
            )
        }
      })
      decode.success(function)
    }),
  )
  decode.success(messages)
}

pub fn ollama_chunk_encode(content) {
  json.object([#("message", json.object([#("content", json.string(content))]))])
  |> json.to_string
  |> string.append("\n")
  |> bit_array.from_string()
}

pub fn submit_first_prompt(prompt) {
  let state = init()
  let #(state, actions) = state.update(state, state.UserUpdatedInput(prompt))
  assert [] == actions
  state.update(state, state.UserSubmittedPrompt)
}

// init default
pub fn init() {
  let config =
    state.Config(
      provider: provider.Ollama(ollama.Config(
        origin: origin.https("eyg.test"),
        api_key: None,
      )),
      origin: origin.https("eyg.test"),
    )
  let #(state, actions) = state.init(config)
  let assert [_] = actions
  state
}
