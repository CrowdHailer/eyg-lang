import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/list
import hub/router
import hub/server/context
import pog
import wisp/simulate

fn test_context() {
  context.Context(
    secret_key_base: "test",
    db: pog.named_connection(process.new_name("router_test")),
  )
}

pub fn public_api_preflight_allows_json_post_test() {
  use path <- list.each([
    "/modules/share", "/packages/submit", "/signatories/submit",
  ])
  let response =
    simulate.request(http.Options, path)
    |> request.set_header("origin", "https://other.example")
    |> request.set_header("access-control-request-method", "POST")
    |> request.set_header("access-control-request-headers", "content-type")
    |> router.route(test_context())

  assert response.status == 204
  assert response.get_header(response, "access-control-allow-origin") == Ok("*")
  assert response.get_header(response, "access-control-allow-methods")
    == Ok("GET, POST")
  assert response.get_header(response, "access-control-allow-headers")
    == Ok("content-type")
  assert simulate.read_body(response) == ""
}

pub fn public_api_error_keeps_cors_headers_test() {
  let response =
    simulate.request(http.Get, "/modules/invalid-cid")
    |> request.set_header("origin", "https://other.example")
    |> router.route(test_context())

  assert response.status == 400
  assert response.get_header(response, "access-control-allow-origin") == Ok("*")
}

pub fn proxy_does_not_grant_cross_origin_access_test() {
  use method <- list.each([http.Options, http.Get, http.Post])
  let response =
    simulate.request(method, "/proxy/unknown/resource")
    |> request.set_header("origin", "https://other.example")
    |> request.set_header("access-control-request-method", "POST")
    |> request.set_header("access-control-request-headers", "content-type")
    |> router.route(test_context())

  assert response.status == 404
  assert response.get_header(response, "access-control-allow-origin")
    == Error(Nil)
  assert response.get_header(response, "access-control-allow-methods")
    == Error(Nil)
  assert response.get_header(response, "access-control-allow-headers")
    == Error(Nil)
}
