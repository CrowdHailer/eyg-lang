import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/javascript/promise
import gleam/result
import midas/browser
import midas/sdk/google
import snag

pub const l = "Google"

pub const lift = t.unit

pub const reply = t.String

pub fn type_() {
  #(l, #(lift, reply))
}

pub const local = google.App(
  "419853920596-v2vh33r5h796q8fjvdu5f4ve16t91rkd.apps.googleusercontent.com",
  "http://localhost:8080",
)

pub fn blocking(app, lift) {
  use Nil <- result.map(cast.as_unit(lift, Nil))
  promise.map(do(app), result_to_eyg)
}

pub fn impl(app, lift) {
  use p <- result.map(blocking(app, lift))
  v.Promise(p)
}

const scopes = [
  "https://www.googleapis.com/auth/calendar.events.readonly",
  "https://www.googleapis.com/auth/gmail.send",
  "https://www.googleapis.com/auth/gmail.readonly",
]

pub fn do(app) {
  browser.run(google.authenticate(app, scopes))
}

fn result_to_eyg(result) {
  case result {
    Ok(token) -> v.ok(v.Str(token))
    Error(reason) -> v.error(v.Str(snag.line_print(reason)))
  }
}
