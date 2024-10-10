import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/io
import gleam/javascript/promise
import gleam/result
import midas/browser
import midas/sdk/twitter
import midas/task
import snag

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

pub fn blocking(client_id, redirect_uri, lift) {
  use content <- result.try(cast.as_string(lift))
  Ok(promise.map(do(client_id, redirect_uri, content), result_to_eyg))
}

// pub fn impl(app, lift) {
//   use p <- result.map(blocking(app, lift))
//   v.Promise(p)
// }

const scopes = ["tweet.read", "tweet.write", "users.read"]

pub fn do(client_id, redirect_uri, content) {
  let task = {
    use token <- task.do(twitter.authenticate(client_id, redirect_uri, scopes))
    twitter.create_tweet(token, content)
  }
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(response) -> v.ok(response_to_eyg(response))
    Error(reason) -> v.error(v.Str(snag.line_print(reason)))
  }
}

fn response_to_eyg(response) {
  io.debug(response)
  v.unit
}
