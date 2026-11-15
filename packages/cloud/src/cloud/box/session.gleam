import cloud/beam/execute
import cloud/beam/file_system
import cloud/box/check
import cloud/box/interface
import cloud/overlay
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/interpreter/cast
import eyg/interpreter/simple_debug
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool
import overlay/policy
import touch_grass/interface as effect

pub fn run(config: check.Module, identity, text, agent, runtime, files) {
  let configuration =
    {
      use mode <- result.try(cast.field("mode", cast.as_string, config.value))
      use policy <- result.map(cast.field(
        "policy",
        policy.decode_policy(interface.rules(), _),
        config.value,
      ))
      #(mode, policy)
    }
    |> result.map_error(simple_debug.describe)
  use #(mode, policy) <- result.try(configuration)
  case mode {
    "shell" -> {
      use source <- result.try(check.parse(text))
      use source <- result.try(check.expand(source, files, "/shell.eyg", []))
      let context =
        infer.pure()
        |> infer.with_effects(
          effect.types(list.map(interface.rules(), fn(rule) { rule.0 })),
        )
      use runtime <- result.try(check.check(
        infer.check(context, source),
        runtime,
      ))
      let #(outcome, runtime, files) =
        execute.source(source, runtime, policy, files, fn(_) { Nil })
      use text <- result.map(outcome)
      #(text, runtime, files)
    }
    "agent" -> {
      let path = "/traces/sessions/" <> identity <> ".json"
      let history = case file_system.read(files, path, 0, 16_777_216) {
        Error(_) -> Ok([])
        Ok(bytes) ->
          bit_array.to_string(bytes)
          |> result.replace_error("Invalid history")
          |> result.try(fn(text) {
            json.parse(text, history_decoder())
            |> result.replace_error("Invalid history")
          })
      }
      use history <- result.try(history)
      let #(history, runtime, files) =
        overlay.inner_loop(
          agent,
          runtime,
          policy,
          [chat.UserMessage(text, []), ..history],
          files,
          fn(_) { Nil },
        )
      let bytes =
        json.array(history, encode_message)
        |> json.to_string
        |> bit_array.from_string
      let #(created, files) =
        file_system.make_directory(files, "/traces/sessions")
      use _ <- result.try(created)
      let #(saved, files) = file_system.write(files, path, bytes)
      use _ <- result.map(saved)
      #(
        history |> list.take(1) |> list.map(chat.text) |> string.join("\n"),
        runtime,
        files,
      )
    }
    _ -> Error("Connection mode must be shell or agent")
  }
}

fn encode_message(message: chat.Message(tool.Call)) {
  let fields = case message {
    chat.UserMessage(text, images) -> [
      #("role", json.string("user")),
      #("text", json.string(text)),
      #("images", json.array(images, json.string)),
    ]
    chat.ToolResultMessage(id, text, images) -> [
      #("role", json.string("tool")),
      #("id", json.string(id)),
      #("text", json.string(text)),
      #("images", json.array(images, json.string)),
    ]
    chat.AssistantMessage(thinking, text, calls) -> [
      #("role", json.string("assistant")),
      #("thinking", json.string(thinking)),
      #("text", json.string(text)),
      #(
        "calls",
        json.array(calls, fn(call) {
          json.object([
            #("id", json.string(call.id)),
            #("name", json.string(call.function.name)),
            #("arguments", utils.fields_to_json(call.function.arguments)),
          ])
        }),
      ),
    ]
  }
  json.object(fields)
}

fn history_decoder() {
  decode.list({
    use role <- decode.field("role", decode.string)
    use text <- decode.field("text", decode.string)
    case role {
      "user" -> {
        use images <- decode.field("images", decode.list(decode.string))
        decode.success(chat.UserMessage(text, images))
      }
      "tool" -> {
        use images <- decode.field("images", decode.list(decode.string))
        use id <- decode.field("id", decode.string)
        decode.success(chat.ToolResultMessage(id, text, images))
      }
      "assistant" -> {
        use thinking <- decode.field("thinking", decode.string)
        use calls <- decode.field(
          "calls",
          decode.list({
            use id <- decode.field("id", decode.string)
            use name <- decode.field("name", decode.string)
            use arguments <- decode.field("arguments", utils.fields_decoder())
            decode.success(tool.Call(id, tool.FunctionCall(name, arguments)))
          }),
        )
        decode.success(chat.AssistantMessage(thinking, text, calls))
      }
      _ -> decode.failure(chat.UserMessage("", []), "history role")
    }
  })
}
