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
