import gleam/list
import oas/generator/utils
import overlay/llm/tool

pub type Message(call) {
  UserMessage(text: String, images: List(String))
  AssistantMessage(thinking: String, text: String, tool_calls: List(call))
  ToolResultMessage(tool_call_id: String, text: String, images: List(String))
}

pub type Arguments =
  utils.Fields

pub type History =
  List(Message(tool.Call))

pub type Completion(call) {
  Completion(thinking: String, content: String, tool_calls: List(call))
}

pub fn from_completion(completion) {
  let Completion(content:, tool_calls:, thinking:) = completion
  AssistantMessage(thinking:, text: content, tool_calls:)
}

pub fn fresh() {
  Completion(thinking: "", content: "", tool_calls: [])
}

pub fn text(message) {
  case message {
    UserMessage(text:, ..) -> text
    AssistantMessage(text:, ..) -> text
    ToolResultMessage(text:, ..) -> text
  }
}

pub fn append_chunks(completion, chunks) {
  let Completion(thinking:, content:, tool_calls:) = completion
  do_append_chunks(chunks, thinking, content, tool_calls)
}

fn do_append_chunks(chunks, thinking, content, tool_calls) {
  case chunks {
    [] -> Completion(thinking:, content:, tool_calls:)
    [Completion(..) as chunk, ..rest] -> {
      do_append_chunks(
        rest,
        thinking <> chunk.thinking,
        content <> chunk.content,
        list.append(tool_calls, chunk.tool_calls),
      )
    }
  }
}
