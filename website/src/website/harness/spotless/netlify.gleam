import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/http
import gleam/http/request
import gleam/javascript/promise
import gleam/option.{None}
import gleam/result.{try}
import midas/browser
import midas/sdk/netlify
import midas/task
import snag
import website/harness/http as harness_http
import website/harness/spotless/proxy

pub const l = "Netlify"

pub fn lift() {
  t.record([
    #("method", t.union([#("GET", t.unit)])),
    #("path", t.String),
    // TODO fix query
    #("query", t.List(t.String)),
    #("headers", t.List(t.String)),
    #("body", t.Binary),
  ])
}

pub fn reply() {
  t.result(
    t.record([
      #("status", t.Integer),
      // TODO proper headers share with lift
      #("headers", t.List(t.String)),
      #("body", t.Binary),
    ]),
    t.String,
  )
}

pub fn type_() {
  #(l, #(lift(), reply()))
}

pub const local = netlify.App(
  "cQmYKaFm-2VasrJeeyobXXz5G58Fxy2zQ6DRMPANWow",
  "http://localhost:8080/auth/netlify",
)

pub const eyg_website = netlify.App(
  "XIBttaoKjHFp_kjsDJYN2Y44dqNA9N9skt6yeTCEfYQ",
  "https://eyg.run/auth/netlify",
)

fn cast(lift) {
  use method <- try(cast.field(
    "method",
    cast.as_varient(_, [#("GET", cast.as_unit(_, http.Get))]),
    lift,
  ))
  use path <- try(cast.field("path", cast.as_string, lift))
  use query <- try(cast.field("query", cast.as_list, lift))
  use headers <- try(cast.field("headers", cast.as_list, lift))
  use body <- try(cast.field("body", cast.as_binary, lift))
  Ok(#(method, path, query, headers, body))
}

pub fn blocking(lift) {
  use #(method, path, query, headers, body) <- try(cast(lift))
  // TODO real app
  Ok(promise.map(do(local, method, path, query, headers, body), result_to_eyg))
}

pub fn preflight(lift) {
  use #(method, path, query, headers, body) <- try(cast(lift))
  // TODO real app
  Ok(fn() {
    promise.map(do(local, method, path, query, headers, body), result_to_eyg)
  })
}

pub fn do(app, method, path, query, headers, body) {
  let task = {
    use token <- task.do(netlify.authenticate(app))
    let request =
      request.new()
      |> request.set_host(api_host)
      |> request.prepend_header("Authorization", "Bearer " <> token)
      |> request.set_method(method)
      |> request.set_path(path)
      |> request.set_body(body)
    use response <- task.do(task.fetch(request))
    task.done(response)
  }
  let task = proxy.proxy(task, http.Https, "eyg.run", None, "/api/netlify")
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(response) -> v.ok(harness_http.response_to_eyg(response))
    Error(reason) -> v.error(v.String(snag.line_print(reason)))
  }
}

pub const api_host = "api.netlify.com"

fn base_request(token) {
  request.new()
  |> request.set_host(api_host)
  |> request.prepend_header("Authorization", "Bearer " <> token)
  |> request.set_body(<<>>)
}
