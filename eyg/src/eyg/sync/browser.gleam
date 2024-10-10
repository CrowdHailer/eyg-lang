import eyg/sync/sync
import gleam/http
import gleam/javascript/promise
import gleam/list
import gleam/option.{Some}
import gleam/uri
import midas/browser
import plinth/browser/window

pub fn get_origin() {
  let assert Ok(location) = uri.parse(window.location())
  let assert uri.Uri(scheme: Some(s), host: Some(h), port: p, ..) = location
  let assert Ok(s) = http.scheme_from_string(s)
  sync.Origin(s, h, p)
}

pub fn do_sync(tasks, message) {
  fn(d) {
    list.map(tasks, fn(t) {
      let #(ref, t) = t
      use result <- promise.map(browser.run(t))
      d(message(sync.HashSourceFetched(ref, result)))
    })
    Nil
  }
}
