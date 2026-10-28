import gleam/dict
import gleam/json
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool

pub fn history_round_trip_test() {
  let history = [
    chat.UserMessage("hi", []),
    chat.AssistantMessage("hmm", "", [
      tool.Call(
        "c1",
        tool.FunctionCall("run", dict.from_list([#("code", utils.String("1"))])),
      ),
    ]),
    chat.ToolResultMessage("c1", "1", []),
    chat.AssistantMessage("", "done", []),
  ]
  let encoded = chat.history_to_json(history) |> json.to_string
  assert json.parse(encoded, chat.history_decoder()) == Ok(history)
}
