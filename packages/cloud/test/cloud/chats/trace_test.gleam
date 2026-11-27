import cloud/chats/event
import cloud/chats/trace
import gleam/dict
import gleam/option.{None, Some}
import overlay/llm/chat
import overlay/llm/tool

pub fn trace_a_chat_test() {
  let call = tool.Call("c1", tool.FunctionCall("run", dict.new()))
  let log = [
    #(2, event.Sent("hello")),
    #(4, event.Replied(chat.Completion("", "", [call]))),
    #(7, event.Returned("c1", Error("failed"))),
    #(9, event.Replied(chat.Completion("", "hi", []))),
  ]
  let assert [chatted, turn, first, called, second] = trace.spans("c", log)
  assert #("chat", 2, 9) == #(chatted.name, chatted.start, chatted.end)
  assert #("turn", 2, 9, None, Some(chatted.id))
    == #(turn.name, turn.start, turn.end, turn.error, turn.parent)
  assert [#("gen_ai.prompt", "hello")] == turn.attributes
  // Asking for a completion starts at the entry before it.
  assert #("chat", True, 2, 4, Some(turn.id))
    == #(first.name, first.client, first.start, first.end, first.parent)
  // A tool call lasts from the completion that made it to its result.
  assert #("tool run", 4, 7, Some("failed"))
    == #(called.name, called.start, called.end, called.error)
  assert #(7, 9) == #(second.start, second.end)
}

pub fn an_unfinished_turn_test() {
  let log = [#(2, event.Sent("hello"))]
  let assert [_, turn] = trace.spans("c", log)
  assert Some("unfinished") == turn.error
}
