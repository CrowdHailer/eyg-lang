import gleam/bit_array
import gleam/dict
import gleam/http/response
import gleam/list
import gleam/string
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/codex
import overlay/llm/tool

fn call() {
  tool.Call(
    id: "call_1",
    function: tool.FunctionCall(
      name: "run",
      arguments: dict.from_list([#("code", utils.String("1"))]),
    ),
  )
}

pub fn request_test() {
  let request =
    codex.completion_request(
      codex.Config("token", "account"),
      "gpt-5.5",
      "be helpful",
      [
        chat.UserMessage("hi", []),
        chat.AssistantMessage("", "", [call()]),
        chat.ToolResultMessage("call_1", "1", []),
      ],
      [tool.Tool("run", "Run code", [])],
    )
  assert request.host == "chatgpt.com"
  assert request.path == "/backend-api/codex/responses"
  assert list.key_find(request.headers, "authorization") == Ok("Bearer token")
  assert list.key_find(request.headers, "chatgpt-account-id") == Ok("account")
  let assert Ok(body) = bit_array.to_string(request.body)
  assert string.contains(body, "\"instructions\":\"be helpful\"")
  assert string.contains(body, "\"store\":false")
  assert string.contains(body, "\"stream\":true")
  assert string.contains(
    body,
    "{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}",
  )
  assert string.contains(
    body,
    "{\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"run\",\"arguments\":\"{\\\"code\\\":\\\"1\\\"}\"}",
  )
  assert string.contains(
    body,
    "{\"type\":\"function_call_output\",\"call_id\":\"call_1\",\"output\":\"1\"}",
  )
  assert string.contains(body, "{\"type\":\"function\",\"name\":\"run\"")
}

const events =
  "event: response.created
data: {\"type\":\"response.created\",\"response\":{}}

event: response.output_item.done
data: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"reasoning\",\"summary\":[{\"type\":\"summary_text\",\"text\":\"thinking\"}]}}

event: response.output_item.done
data: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"Running\"}]}}

event: response.output_item.done
data: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"run\",\"arguments\":\"{\\\"code\\\":\\\"1\\\"}\"}}

event: response.completed
data: {\"type\":\"response.completed\",\"response\":{}}

"

pub fn completion_response_test() {
  let response = response.new(200) |> response.set_body(<<events:utf8>>)
  assert codex.completion_response(response)
    == Ok(
      chat.Completion(thinking: "thinking", content: "Running", tool_calls: [
        call(),
      ]),
    )
}

pub fn chunks_are_buffered_test() {
  let #(first, rest) =
    string.split_once(events, "event: response.completed") |> unwrap
  let assert #([], remaining) =
    codex.completion_chunk_parse(<<>>, <<first:utf8>>)
  let assert #([completion], <<>>) =
    codex.completion_chunk_parse(remaining, <<
      "event: response.completed":utf8,
      rest:utf8,
    >>)
  assert completion.content == "Running"
}

fn unwrap(result) {
  let assert Ok(value) = result
  value
}

pub fn failed_response_test() {
  let body =
    "data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"rate_limit\",\"message\":\"usage limit reached\"}}}\n\n"
  let response = response.new(200) |> response.set_body(<<body:utf8>>)
  assert codex.completion_response(response) == Error("usage limit reached")
}

pub fn one_byte_utf8_and_split_terminal_event_test() {
  let events = string.replace(events, "Running", "你好 🌱")
  let #(parts, remaining) = one_byte_chunks(<<events:utf8>>, <<>>, [])
  let assert [completion] = parts
  assert completion.content == "你好 🌱"
  // The only remaining bytes after a completed event are its line terminators.
  assert bit_array.to_string(remaining) == Ok("\n\n")
  let assert Ok(finished) =
    provider.finish_stream(
      provider.Codex(codex.Config("fixture", "account")),
      <<events:utf8>>,
      chat.fresh(),
    )
  assert finished == completion
}

fn one_byte_chunks(bytes, remaining, parts) {
  case bytes {
    <<byte, rest:bytes>> -> {
      let #(new, remaining) = codex.completion_chunk_parse(remaining, <<byte>>)
      one_byte_chunks(rest, remaining, list.append(parts, new))
    }
    _ -> #(parts, remaining)
  }
}

pub fn literal_terminal_name_does_not_finish_a_stream_test() {
  let text =
    "data: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"message\",\"content\":[{\"text\":\"response.completed\"}]}}\n\n"
  assert codex.completion_chunk_parse(<<>>, <<text:utf8>>)
    == #([], <<text:utf8>>)
  let partial = <<
    text:utf8,
    "data: {\"type\":\"response.completed\",\"response\":",
  >>
  assert codex.completion_chunk_parse(<<>>, partial) == #([], partial)
}

pub fn completed_output_is_authoritative_without_duplicate_items_test() {
  let body =
    string.replace(
      events,
      "{\"type\":\"response.completed\",\"response\":{}}",
      "{\"type\":\"response.completed\",\"response\":{\"output\":[{\"type\":\"message\",\"content\":[{\"text\":\"final\"}]}]}}",
    )
  let reply = response.new(200) |> response.set_body(<<body:utf8>>)
  assert codex.completion_response(reply)
    == Ok(chat.Completion("", "final", []))
}

pub fn missing_terminal_incomplete_and_bad_arguments_are_failures_test() {
  let provider = provider.Codex(codex.Config("fixture", "account"))
  let assert Error(_) =
    provider.finish_stream(
      provider,
      <<"data: {\"type\":\"response.created\"}\n">>,
      chat.fresh(),
    )
  let incomplete = <<
    "data: {\"type\":\"response.incomplete\",\"response\":{\"incomplete_details\":{\"reason\":\"max_output_tokens\"}}}\n\n",
  >>
  assert provider.finish_stream(provider, incomplete, chat.fresh())
    == Error("response incomplete: max_output_tokens")
  let failed = <<"data: {\"type\":\"response.failed\"}\n\n">>
  assert provider.finish_stream(provider, failed, chat.fresh())
    == Error("response failed")
  let bad = string.replace(events, "{\\\"code\\\":\\\"1\\\"}", "not JSON")
  let assert Error(_) =
    provider.finish_stream(provider, <<bad:utf8>>, chat.fresh())
  assert provider.id(provider) == "openai-codex"
}
