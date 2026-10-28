//// Browser setup and seed parsing are Gleam; the HTML only starts this module.

import eyg/embed/browser
import gleam/bit_array
import gleam/http/request
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import gleam/uri
import hashi
import plinthx/browser/html
import plinthx/javascript/module

fn text(url) {
  let assert Ok(request) = request.to(url)
  use response <- promise.map(browser.send(request.set_body(request, <<>>)))
  let assert Ok(response) = response
  assert response.status == 200
  let assert Ok(text) = bit_array.to_string(response.body)
  text
}

pub fn seed(search: String) {
  uri.parse_query(string.drop_start(search, 1))
  |> result.unwrap([])
  |> list.key_find("seed")
  |> result.try(int.parse)
  |> result.unwrap(1)
}

pub fn main() {
  let origin = string.replace(module.url(), "/app.mjs", "")
  let assert Ok(location) = html.get_location()
  use library <- promise.await(text(origin <> "/library.eyg"))
  use guide <- promise.map(text(origin <> "/syntax.md"))
  hashi.main(library, guide, seed(html.search(location)), origin)
}
