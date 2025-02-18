import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result
import midas/browser
import midas/sdk/netlify
import snag

pub const l = "Netlify"

pub const lift = t.unit

pub const reply = t.String

pub fn type_() {
  #(l, #(lift, reply))
}

pub const local = netlify.App(
  "cQmYKaFm-2VasrJeeyobXXz5G58Fxy2zQ6DRMPANWow",
  "http://localhost:8080/auth/netlify",
)

pub const eyg_website = netlify.App(
  "XIBttaoKjHFp_kjsDJYN2Y44dqNA9N9skt6yeTCEfYQ",
  "https://eyg.run/auth/netlify",
)

pub fn blocking(app, lift) {
  use Nil <- result.map(cast.as_unit(lift, Nil))
  promise.map(do(app), result_to_eyg)
}

pub fn impl(app, lift) {
  use p <- result.map(blocking(app, lift))
  v.Promise(p)
}

pub fn do(app) {
  browser.run(netlify.authenticate(app))
}

fn result_to_eyg(result) {
  case result {
    Ok(token) -> v.ok(v.String(token))
    Error(reason) -> v.error(v.String(snag.line_print(reason)))
  }
}
