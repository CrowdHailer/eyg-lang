import eyg/interpreter/value as v
import gleam/http as ghttp
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{Some}
import gleam/string
import touch_grass/http

pub fn method_test() {
  use method <- list.each([
    ghttp.Get,
    ghttp.Post,
    ghttp.Head,
    ghttp.Put,
    ghttp.Delete,
    ghttp.Trace,
    ghttp.Connect,
    ghttp.Options,
    ghttp.Patch,
    ghttp.Other("other"),
  ])
  let assert v.Tagged(label:, ..) as value = http.method_to_eyg(method)
  assert string.uppercase(ghttp.method_to_string(method)) == label
  let assert Ok(recovered) = http.method_to_gleam(value)
  assert method == recovered
}

pub fn scheme_test() {
  use method <- list.each([
    ghttp.Http,
    ghttp.Https,
  ])
  let assert v.Tagged(label:, ..) as value = http.scheme_to_eyg(method)
  assert string.uppercase(ghttp.scheme_to_string(method)) == label
  let assert Ok(recovered) = http.scheme_to_gleam(value)
  assert method == recovered
}

pub fn headers_test() {
  let headers = [#("content-type", "text"), #("x-foo", "abc")]
  let value = http.headers_to_eyg(headers)
  let assert Ok(recovered) = http.headers_to_gleam(value)
  assert headers == recovered
}

pub fn rquest_test() {
  let request =
    request.Request(
      method: ghttp.Get,
      headers: [#("content-type", "application/json")],
      body: <<"content">>,
      scheme: ghttp.Http,
      host: "eyg.run",
      port: Some(1111),
      path: "/abc",
      query: Some("x=1"),
    )
  let value = http.request_to_eyg(request)
  let assert Ok(recovered) = http.request_to_gleam(value)
  assert request == recovered
}

pub fn response_test() {
  let request =
    response.Response(
      status: 234,
      headers: [#("content-type", "image/png")],
      body: <<"your image">>,
    )
  let value = http.response_to_eyg(request)
  let assert Ok(recovered) = http.response_to_gleam(value)
  assert request == recovered
}
