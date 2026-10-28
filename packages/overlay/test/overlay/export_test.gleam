import gleam/dict
import gleam/json
import gleam/string
import oas/generator/utils
import overlay/export
import overlay/llm/chat
import overlay/llm/tool

fn session() {
  export.Session(
    id: "ses_1",
    directory: "/project",
    provider_id: "ollama",
    model_id: "glm",
    time: 100,
  )
}

fn call(id) {
  tool.Call(
    id:,
    function: tool.FunctionCall(
      name: "run",
      arguments: dict.from_list([#("code", utils.String("1"))]),
    ),
  )
}

pub fn export_test() {
  let history = [
    chat.UserMessage("Add numbers\nplease", []),
    chat.AssistantMessage("hmm", "", [call("")]),
    chat.ToolResultMessage("", "1", []),
    chat.AssistantMessage("", "The answer is 1", []),
  ]
  let exported = export.encode(session(), history) |> json.to_string
  assert string.contains(
    exported,
    "\"info\":{\"id\":\"ses_1\",\"slug\":\"add-numbers\",\"projectID\":\"overlay\",\"directory\":\"/project\",\"title\":\"Add numbers\"",
  )
  // The user message
  assert string.contains(
    exported,
    "{\"info\":{\"id\":\"msg_000001\",\"sessionID\":\"ses_1\",\"role\":\"user\"",
  )
  assert string.contains(
    exported,
    "\"type\":\"text\",\"text\":\"Add numbers\\nplease\"",
  )
  // The assistant message with reasoning and a completed tool call
  assert string.contains(
    exported,
    "\"id\":\"msg_000002\",\"sessionID\":\"ses_1\",\"role\":\"assistant\"",
  )
  assert string.contains(exported, "\"parentID\":\"msg_000001\"")
  assert string.contains(exported, "\"type\":\"reasoning\",\"text\":\"hmm\"")
  assert string.contains(
    exported,
    "\"type\":\"tool\",\"callID\":\"\",\"tool\":\"run\",\"state\":{\"status\":\"completed\",\"input\":{\"code\":\"1\"},\"output\":\"1\"",
  )
  // Tool results are not messages of their own
  assert !string.contains(exported, "msg_000004")
  assert string.contains(exported, "\"text\":\"The answer is 1\"")
}

pub fn missing_result_test() {
  let history = [
    chat.UserMessage("go", []),
    chat.AssistantMessage("", "", [call("a")]),
  ]
  let exported = export.encode(session(), history) |> json.to_string
  assert string.contains(exported, "\"status\":\"error\"")
}
