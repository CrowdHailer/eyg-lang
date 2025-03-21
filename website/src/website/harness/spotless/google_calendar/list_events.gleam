import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import midas/browser
import midas/sdk/google
import midas/sdk/google/calendar
import midas/task
import snag

pub const l = "GoogleCalendar.ListEvents"

pub fn lift() {
  t.String
}

pub fn reply() {
  t.result(
    t.List(
      t.record([
        #("start", t.String),
        #("summary", t.String),
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
  use start_time <- result.try(cast.as_string(lift))
  Ok(promise.map(do(app, start_time), result_to_eyg))
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

pub fn do(app, start_time) {
  let task = {
    use token <- task.do(google.authenticate(app, scopes))
    use user_id <- task.do(google.userinfo(token))
    calendar.list_events(token, user_id, start_time)
  }
  browser.run(task)
}

fn result_to_eyg(result) {
  case result {
    Ok(events) -> v.ok(v.LinkedList(list.map(events, event_to_eyg)))
    Error(reason) -> v.error(v.String(snag.line_print(reason)))
  }
}

fn event_to_eyg(message) {
  let calendar.Event(start: start, summary: summary, ..) = message
  v.Record(
    dict.from_list([
      #("start", v.String(string.inspect(start))),
      #("summary", v.String(summary)),
    ]),
  )
}
