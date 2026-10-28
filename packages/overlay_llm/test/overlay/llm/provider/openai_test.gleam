import gleam/bit_array
import gleam/dict
import gleam/http/response
import gleam/list
import gleam/option.{Some}
import gleam/string
import oas/generator/utils
import ogre/origin
import overlay/llm/chat
import overlay/llm/provider/openai
import overlay/llm/tool

fn config() {
  openai.Config(
    origin: origin.https("openrouter.ai"),
    path: "/api/v1/chat/completions",
    api_key: Some("key"),
    headers: [#("x-title", "overlay")],
  )
}

pub fn completion_request_test() {
  let call =
    tool.Call(
      id: "c1",
      function: tool.FunctionCall(
        name: "run",
        arguments: dict.from_list([#("code", utils.String("1"))]),
      ),
    )
  let request =
    openai.completion_request(
      config(),
      "gpt",
      "system",
      [
        chat.UserMessage("hi", []),
        chat.AssistantMessage("", "", [call]),
        chat.ToolResultMessage("c1", "1", []),
      ],
      [],
    )
  assert request.host == "openrouter.ai"
  assert request.path == "/api/v1/chat/completions"
  assert list.key_find(request.headers, "x-title") == Ok("overlay")
  assert list.key_find(request.headers, "authorization") == Ok("Bearer key")
  let assert Ok(body) = bit_array.to_string(request.body)
  assert string.contains(body, "\"stream\":false")
  // arguments are sent as a JSON string
  assert string.contains(body, "\"arguments\":\"{\\\"code\\\":\\\"1\\\"}\"")
  assert string.contains(body, "\"tool_call_id\":\"c1\"")
}

pub fn completion_response_test() {
  let body =
    "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"run\",\"arguments\":\"{\\\"code\\\":\\\"1\\\"}\"}}]}}]}"
  let response = response.new(200) |> response.set_body(<<body:utf8>>)
  let assert Ok(chat.Completion(content: "", tool_calls: [call], ..)) =
    openai.completion_response(response)
  assert call.id == "c1"
  assert call.function.name == "run"
  assert dict.get(call.function.arguments, "code") == Ok(utils.String("1"))
}

pub fn error_response_test() {
  let response =
    response.new(401) |> response.set_body(<<"{\"error\":\"bad\"}":utf8>>)
  assert openai.completion_response(response)
    == Error("unexpected status: 401 {\"error\":\"bad\"}")
}

pub fn streamed_events_are_joined_test() {
  let events = [
    "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n",
    "data: {\"choices\":[{\"delta\":{\"content\":\"lo\",\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"function\":{\"name\":\"run\",\"arguments\":\"{\\\"co\"}}]}}]}\n",
    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"de\\\":\\\"1\\\"}\"}}]}}]}\n",
    "data: [DONE]\n",
  ]
  let #(completions, remaining) =
    list.fold(events, #([], <<>>), fn(acc, event) {
      let #(completions, remaining) = acc
      let #(new, remaining) =
        openai.completion_chunk_parse(remaining, <<event:utf8>>)
      #(list.append(completions, new), remaining)
    })
  assert remaining == <<>>
  let assert [chat.Completion(content: "Hello", tool_calls: [call], ..)] =
    completions
  assert call.id == "c1"
  assert dict.get(call.function.arguments, "code") == Ok(utils.String("1"))
}

pub fn streamed_requests_ask_for_reported_token_usage_test() {
  let request =
    openai.stream_completion_request(config(), "fixture", "", [], [])
  let assert Ok(body) = bit_array.to_string(request.body)
  assert string.contains(body, "\"include_usage\":true")
}

pub fn text_containing_the_done_marker_does_not_finish_the_stream_test() {
  let line =
    "data: {\"choices\":[{\"delta\":{\"content\":\"literal data: [DONE]\"}}]}\n"
  let #(events, pending) = openai.completion_chunk_parse(<<>>, <<line:utf8>>)
  assert events == []
  assert pending == <<line:utf8>>
  let #(events, _) =
    openai.completion_chunk_parse(pending, <<"data: [DONE]\n">>)
  let assert [chat.Completion(content: "literal data: [DONE]", ..)] = events
}

pub fn split_utf8_and_crlf_events_keep_multiple_tool_call_indices_test() {
  let line =
    "data: {\"choices\":[{\"delta\":{\"content\":\"🌱\",\"tool_calls\":[{\"index\":1,\"id\":\"b\",\"function\":{\"name\":\"run\",\"arguments\":\"{\\\"code\\\":\\\"2\\\"}\"}},{\"index\":0,\"id\":\"a\",\"function\":{\"name\":\"run\",\"arguments\":\"{\\\"code\\\":\\\"1\\\"}\"}}]}}]}\r\ndata: [DONE]\r\n"
  let bytes = bit_array.from_string(line)
  let size = bit_array.byte_size(bytes)
  let events =
    list.fold(list.repeat(Nil, size), #(0, <<>>, []), fn(acc, _) {
      let #(index, pending, seen) = acc
      let assert Ok(byte) = bit_array.slice(bytes, index, 1)
      let #(new, pending) = openai.completion_chunk_parse(pending, byte)
      #(index + 1, pending, list.append(seen, new))
    }).2
  let assert [chat.Completion(content: "🌱", tool_calls: [first, second], ..)] =
    events
  assert first.id == "a" && second.id == "b"
  assert dict.get(first.function.arguments, "code") == Ok(utils.String("1"))
  assert dict.get(second.function.arguments, "code") == Ok(utils.String("2"))
}
