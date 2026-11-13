import gleam/bit_array
import gleam/dict
import gleam/http/response
import gleam/list
import gleam/option.{None}
import gleam/string
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/bedrock
import overlay/llm/sigv4
import overlay/llm/tool

fn config() {
  bedrock.Config("eu-west-1", sigv4.Credentials("AKID", "secret", None))
}

fn call() {
  tool.Call(
    "t1",
    tool.FunctionCall("run", dict.from_list([#("code", utils.String("1"))])),
  )
}

pub fn request_test() {
  let request =
    bedrock.completion_request(
      config(),
      "anthropic.claude-sonnet:0",
      "system",
      [
        chat.UserMessage("hi", []),
        chat.AssistantMessage("", "", [call()]),
        chat.ToolResultMessage("t1", "1", []),
        chat.UserMessage("and?", []),
      ],
      [tool.Tool("run", "Run", [])],
    )
  assert request.host == "bedrock-runtime.eu-west-1.amazonaws.com"
  assert request.path == "/model/anthropic.claude-sonnet%3A0/converse"
  let assert Ok(authorization) = list.key_find(request.headers, "authorization")
  assert string.starts_with(authorization, "AWS4-HMAC-SHA256 Credential=AKID/")
  let assert Ok(body) = bit_array.to_string(request.body)
  assert string.contains(body, "\"system\":[{\"text\":\"system\"}]")
  // The tool result and the next prompt are one user message
  assert string.contains(
    body,
    "{\"role\":\"user\",\"content\":[{\"toolResult\":{\"toolUseId\":\"t1\",\"content\":[{\"text\":\"1\"}]}},{\"text\":\"and?\"}]}",
  )
  assert string.contains(
    body,
    "{\"role\":\"assistant\",\"content\":[{\"toolUse\":{\"toolUseId\":\"t1\",\"name\":\"run\",\"input\":{\"code\":\"1\"}}}]}",
  )
}

pub fn response_test() {
  let body =
    "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"Running\"},{\"toolUse\":{\"toolUseId\":\"t1\",\"name\":\"run\",\"input\":{\"code\":\"1\"}}}]}},\"stopReason\":\"tool_use\"}"
  let response = response.new(200) |> response.set_body(<<body:utf8>>)
  assert bedrock.completion_response(response)
    == Ok(
      chat.Completion(thinking: "", content: "Running", tool_calls: [call()]),
    )
  let assert #([], remaining) =
    bedrock.completion_chunk_parse(<<>>, <<string.slice(body, 0, 20):utf8>>)
  let assert #([completion], <<>>) =
    bedrock.completion_chunk_parse(remaining, <<
      string.drop_start(body, 20):utf8,
    >>)
  assert completion.content == "Running"
}

pub fn fragmented_unicode_test() {
  let body = <<
    "{\"output\":{\"message\":{\"content\":[{\"text\":\"你好 🌱\"},{\"reasoningContent\":{\"reasoningText\":{\"text\":\"thinking\"}}}]}},\"usage\":{\"inputTokens\":7,\"outputTokens\":3}}":utf8,
  >>
  let #(parts, remaining) = one_byte_chunks(body, <<>>, [])
  assert remaining == <<>>
  assert parts == [chat.Completion("thinking", "你好 🌱", [])]
  let assert [completion] = parts
  assert provider.finish_stream(provider.Bedrock(config()), body, chat.fresh())
    == Ok(completion)
}

fn one_byte_chunks(bytes, remaining, parts) {
  case bytes {
    <<byte, rest:bytes>> -> {
      let #(new, remaining) =
        bedrock.completion_chunk_parse(remaining, <<byte>>)
      one_byte_chunks(rest, remaining, list.append(parts, new))
    }
    _ -> #(parts, remaining)
  }
}

pub fn incomplete_or_error_document_is_not_a_completion_test() {
  let provider = provider.Bedrock(config())
  let assert Error(_) =
    provider.finish_stream(provider, <<"{\"output\":">>, chat.fresh())
  let assert Error(_) =
    provider.finish_stream(
      provider,
      <<"{\"message\":\"denied\"}">>,
      chat.fresh(),
    )
  let error = response.new(403) |> response.set_body(<<"denied">>)
  assert bedrock.completion_response(error)
    == Error("unexpected status: 403 denied")
}
