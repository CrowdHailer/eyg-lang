import eyg/embed/browser
import gleam/bit_array
import gleam/http/request
import gleam/javascript/promise
import gleam/string
import lustre
import native/app
import plinthx/javascript/module

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
  let application = lustre.application(app.init, app.update, app.view)
  let assert Ok(_) =
    lustre.start(application, "#app", app.Flags(library:, guide:, origin:))
  Nil
}
