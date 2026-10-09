import gleam/http/response
import overlay/llm/provider/ollama

pub fn error_response_includes_body_test() {
  let response =
    response.new(401)
    |> response.set_body(<<"{\"error\":\"unauthorized\"}":utf8>>)
  assert ollama.completion_response(response)
    == Error("unexpected status: 401 {\"error\":\"unauthorized\"}")
}

pub fn error_response_without_body_test() {
  let response = response.new(500) |> response.set_body(<<>>)
  assert ollama.completion_response(response) == Error("unexpected status: 500")
}

pub fn chunk_split_inside_character_test() {
  let line = "{\"message\":{\"content\":\"é\"}}\n"
  let assert <<first:bytes-size(24), rest:bits>> = <<line:utf8>>
  let assert #([], remaining) = ollama.completion_chunk_parse(<<>>, first)
  let assert #([completion], <<>>) =
    ollama.completion_chunk_parse(remaining, rest)
  assert completion.content == "é"
}

pub fn error_event_is_returned_as_content_test() {
  let assert #([completion], <<>>) =
    ollama.completion_chunk_parse(<<>>, <<
      "{\"error\":\"model not found\"}\n":utf8,
    >>)
  assert completion.content == "Error: model not found"
}
