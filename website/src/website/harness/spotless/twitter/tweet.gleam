import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/http
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/option.{None}
import gleam/result
import midas/browser
import midas/sdk/twitter
import midas/task
import snag
import website/harness/spotless/proxy

pub const l = "Twitter.Tweet"

pub fn lift() {
  t.String
}

pub fn reply() {
  t.result(
    t.record([
      #("id", t.String),
      #("thread_id", t.String),
      #("label_ids", t.List(t.String)),
    ]),
    t.String,
  )
}

pub fn type_() {
  #(l, #(lift(), reply()))
}

pub fn blocking(client_id, redirect_uri, local, lift) {
  use content <- result.try(cast.as_string(lift))
  Ok(promise.map(do(client_id, redirect_uri, local, content), result_to_eyg))
}

// fn impl(app, lift) {
//   use p <- result.map(blocking(app, lift))
//   v.Promise(p)
// }

const scopes = ["tweet.read", "tweet.write", "users.read"]

fn authenticate(client_id, redirect_uri, local, scopes) {
  let state = int.to_string(int.random(1_000_000_000))
  let state = case local {
    True -> "LOCAL" <> state
    False -> state
  }
  let challenge = int.to_string(int.random(1_000_000_000))
  twitter.do_authenticate(client_id, redirect_uri, scopes, state, challenge)
}

pub fn do(client_id, redirect_uri, local, content) {
  let task = {
    use token <- task.do(authenticate(client_id, redirect_uri, local, scopes))
    twitter.create_tweet(token, content)
  }
  let task = proxy.proxy(task, http.Https, "eyg.run", None, "/api/twitter")
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(response) -> v.ok(response_to_eyg(response))
    Error(reason) -> v.error(v.String(snag.line_print(reason)))
  }
}

fn response_to_eyg(response) {
  io.debug(response)
  v.unit()
}
