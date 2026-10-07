import eyg/cli/overlay
import gleam/string
import overlay/llm/chat
import overlay/llm/tool

pub fn result_messages_bound_text_and_preserve_call_metadata_test() {
  let large = string.repeat("x", 30_000)
  let assert chat.ToolResultMessage(tool_call_id:, text:, images:) =
    overlay.result_to_message("call-1", Ok(tool.Return(large, ["image"])))
  assert tool_call_id == "call-1"
  assert images == ["image"]
  assert string.contains(text, "6000 characters omitted")
  assert string.length(text) < 24_200

  let assert chat.ToolResultMessage(tool_call_id:, text:, images:) =
    overlay.result_to_message("call-2", Error(large))
  assert tool_call_id == "call-2"
  assert images == []
  assert string.contains(text, "6000 characters omitted")
  assert string.length(text) < 24_200
}

pub fn ordinary_error_messages_are_preserved_test() {
  assert overlay.result_to_message("call-3", Error("missing record field: x"))
    == chat.ToolResultMessage("call-3", "missing record field: x", [])
}
