import gleam/fetch
import gleam/http/request
import gleam/http/response
import gleam/javascript/promise
import gleeunit/should
import overlay/eval
import overlay/eval/model
import overlay/llm/provider
import overlay/llm/provider/ollama as overlay_ollama

pub fn replay_does_not_need_cloud_credentials_test() {
  let assert Ok(model.Provider(
    llm: provider.Llm(provider: provider.Ollama(config), ..),
    ..,
  )) = eval.model_for_replay("ollama:fixture")
  assert config == overlay_ollama.cloud("cassette")
  let assert Ok(model.Provider(
    llm: provider.Llm(provider: provider.Mistral(config), ..),
    ..,
  )) = eval.model_for_replay("mistral:fixture")
  assert config.api_key == "cassette"
}

pub fn a_stream_that_stalls_after_headers_times_out_test() {
  let transport = fn(_) {
    promise.resolve(
      Ok(response.Response(200, [], fn() { promise.new(fn(_) { Nil }) })),
    )
  }
  let limited = model.with_timeout(transport, 1)
  let assert Ok(request) = request.to("https://fixture.example.com/chat")
  use response <- promise.await(limited(request.set_body(request, <<>>)))
  let assert Ok(response) = response
  use result <- promise.map(response.body())
  result |> should.equal(Error(fetch.NetworkError("no answer within 1s")))
}
