//// Load the bundled page resources and start Lustre from a native module entry.

import eyg/embed/browser
import gleam/bit_array
import gleam/http/request
import gleam/javascript/promise
import gleam/string
import plinthx/javascript/module
import todomvc

fn text(url) {
  let assert Ok(request) = request.to(url)
  use reply <- promise.map(browser.send(request.set_body(request, <<>>)))
  let assert Ok(reply) = reply
  assert reply.status == 200
  let assert Ok(text) = bit_array.to_string(reply.body)
  text
}

pub fn main() {
  let origin = string.replace(module.url(), "/app.mjs", "")
  use library <- promise.await(text(origin <> "/library.eyg"))
  use guide <- promise.map(text(origin <> "/syntax.md"))
  todomvc.main(library, guide, origin)
}
