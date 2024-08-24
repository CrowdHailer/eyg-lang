import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/result
import midas/browserx
import midas/sdk/google
import midas/sdk/google/gmail
import midas/task
import snag

pub const l = "Gmail.Send"

pub fn lift() {
  t.record([#("to", t.String), #("message", t.String)])
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

pub fn blocking(app, lift) {
  use to <- result.try(cast.field("to", cast.as_string, lift))
  use message <- result.try(cast.field("message", cast.as_string, lift))
  Ok(promise.map(do(app, to, message), result_to_eyg))
}

// pub fn impl(app, lift) {
//   use p <- result.map(blocking(app, lift))
//   v.Promise(p)
// }

const scopes = [
  "https://www.googleapis.com/auth/calendar.events.readonly",
  "https://www.googleapis.com/auth/gmail.send",
  "https://www.googleapis.com/auth/gmail.readonly", "openid", "email",
]

pub fn do(app, to, message) {
  let task = {
    use token <- task.do(google.authenticate(app, scopes))
    use email <- task.do(google.userinfo(token))
    gmail.send(token, email, to, message)
  }
  browserx.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(message) -> v.ok(message_to_eyg(message))
    Error(reason) -> v.error(v.Str(snag.line_print(reason)))
  }
}

fn message_to_eyg(message) {
  let gmail.Message(id, thread_id) = message
  v.Record([
    #("id", v.Str(id)),
    #("thread_id", v.Str(thread_id)),
    // #("label_ids", v.LinkedList(list.map(label_ids, v.Str))),
  ])
}
