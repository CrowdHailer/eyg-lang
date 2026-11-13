import gleam/http
import gleam/http/request
import gleam/http/response
import overlay/eval/environment

pub fn requests_are_offline_unless_a_fixture_answers_test() {
  let assert Ok(request) = request.to("https://example.test/data")
  let request = request.set_body(request, <<>>)
  let env = environment.empty()
  let assert environment.Refused(_) = environment.answer(env, request)
  let response = response.new(200) |> response.set_body(<<"fixture">>)
  let env =
    environment.route(env, http.Get, "https://example.test/data", response)
  assert environment.Answered(response) == environment.answer(env, request)
  let assert environment.Refused(_) =
    environment.answer(env, request.set_method(request, http.Post))
}

pub fn missing_own_pages_never_fall_through_to_the_network_test() {
  let assert Ok(request) = request.to("https://eyg.run/missing")
  let env =
    environment.Environment(..environment.empty(), network: environment.Online)
  let assert environment.Answered(response) =
    environment.answer(env, request.set_body(request, <<>>))
  assert 404 == response.status
}
