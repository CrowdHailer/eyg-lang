import gleam/dict
import gleam/option.{None}
import oas/generator/utils
import ogre/origin
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/ollama
import overlay/llm/tool
import overlay/web/state

fn config() -> state.Config {
  let origin = origin.https("eyg.test")
  state.Config(
    provider: provider.Ollama(ollama.Config(origin:, api_key: None)),
    origin:,
  )
}

pub fn state() {
  state.State(..state.new(config()), history: [
    chat.ToolResultMessage(tool_call_id: "abc", text: "5", images: []),
    chat.AssistantMessage(
      thinking: "",
      text: "Thats a really long and interesting question I will start by looking into the details and running a script to access all the files",
      tool_calls: [run_code("abc", "!int_add(1, 2)")],
    ),
    chat.UserMessage(
      text: "Hello

1. one
2. three",
      images: [],
    ),
  ])
}

fn run_code(id, code) {
  tool.Call(
    id:,
    function: tool.FunctionCall(
      name: "run",
      arguments: dict.from_list([
        #("code", utils.String(code)),
      ]),
    ),
  )
}
