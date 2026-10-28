//// Local delayed HTTP fixtures, with request logging for capture verification.

import gleam/javascript/array.{type Array}
import gleam/javascript/promise
import gleam/result
import gleam/uri
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/javascript/array as native_array

pub type Demo {
  Demo(server: server.Server, requests: Array(#(String, Int)))
}

pub fn response(
  body: String,
  status: Int,
  content_type: String,
) -> fetch.Response {
  let assert Ok(constructor) = fetch.get_response()
  let assert Ok(response) =
    fetch.new_response(constructor, body, status, [
      #("content-type", content_type),
    ])
  response
}

pub fn route(path: String) -> #(Int, Int, String) {
  case path {
    "/plan" -> #(70, 200, "Plan: look up the local evidence\n")
    "/tool" -> #(
      150,
      200,
      "Evidence: effects provide the observation boundary\n",
    )
    "/answer" -> #(90, 200, "Answer: trace the effects, then inspect the run\n")
    "/unavailable" -> #(45, 503, "Try again after a short wait\n")
    _ -> #(0, 404, "Unknown fixture\n")
  }
}

pub fn start(port: Int) -> Result(Demo, String) {
  use bun <- result.try(
    runtime.get() |> result.replace_error("Bun is required"),
  )
  let requests = array.from_list([])
  use server <- result.map(server.serve(
    bun,
    server.Options(port, "127.0.0.1", fn(request) {
      let path = case uri.parse(fetch.request_url(request)) {
        Ok(url) -> url.path
        Error(_) -> ""
      }
      let #(delay, status, body) = route(path)
      let assert Ok(_) = native_array.push(requests, #(path, status))
      use Nil <- promise.map(promise.wait(delay))
      response(body, status, "text/plain; charset=utf-8")
    }),
  ))
  Demo(server, requests)
}
