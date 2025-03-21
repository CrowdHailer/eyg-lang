import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/javascript/promise
import gleam/list
import gleam/result
import midas/browser
import midas/sdk/google
import midas/sdk/google/gmail
import midas/task
import snag

pub const l = "Gmail.ListMessages"

pub fn lift() {
  t.unit
}

pub fn reply() {
  t.result(
    t.List(
      t.record([
        #("id", t.String),
        #("thread_id", t.String),
        #("label_ids", t.List(t.String)),
      ]),
    ),
    t.String,
  )
}

pub fn type_() {
  #(l, #(lift(), reply()))
}

pub fn blocking(app, lift) {
  use Nil <- result.try(cast.as_unit(lift, Nil))
  Ok(promise.map(do(app), result_to_eyg))
}

fn impl(app, lift) {
  use p <- result.map(blocking(app, lift))
  v.Promise(p)
}

const scopes = [
  "https://www.googleapis.com/auth/calendar.events.readonly",
  "https://www.googleapis.com/auth/gmail.send",
  "https://www.googleapis.com/auth/gmail.readonly", "openid", "email",
]

pub fn do(app) {
  let task = {
    use token <- task.do(google.authenticate(app, scopes))
    use user_id <- task.do(google.userinfo(token))
    gmail.list_messages(token, user_id)
  }
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(messages) -> v.ok(v.LinkedList(list.map(messages, message_to_eyg)))
    Error(reason) -> v.error(v.String(snag.line_print(reason)))
  }
}

fn message_to_eyg(message) {
  let gmail.Message(id, thread_id) = message
  v.Record(
    dict.from_list([
      #("id", v.String(id)),
      #("thread_id", v.String(thread_id)),
      // #("label_ids", v.LinkedList(list.map(label_ids, v.String))),
    ]),
  )
}
