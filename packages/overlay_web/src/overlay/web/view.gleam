//// ViewModel for the core state

import gleam/list
import overlay/llm/chat
import overlay/web/state.{type State, State}

pub fn messages(state: State) {
  let State(status:, history:, ..) = state
  let messages = case status {
    state.Waiting -> history
    state.Asking(messages:) -> list.append(messages, state.history)
    state.Streaming(reader: _, completion:) -> {
      let chat.Completion(thinking:, content:, tool_calls:) = completion
      let message = chat.AssistantMessage(thinking:, text: content, tool_calls:)
      [message, ..history]
    }
    state.Executing(_calls) -> history
  }
  let length = list.length(messages)
  list.index_map(messages, fn(message, i) { #(length - i, message) })
}
