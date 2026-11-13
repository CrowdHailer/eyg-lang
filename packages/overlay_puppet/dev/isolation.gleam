//// Browser check fixture; compiled by the same Gleam bundler as the preview driver.

import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import plinthx/browser/fetch
import plinthx/browser/node as dom

fn status(result: Result(a, b)) {
  case result {
    Ok(_) -> "accessible"
    Error(_) -> "blocked"
  }
}

pub fn main() {
  let body = dom.body()
  dom.set_attribute(body, "data-executed", "yes")
  dom.set_attribute(
    body,
    "data-cookie",
    status(dom.try_text(dom.document(), "cookie")),
  )
  dom.set_attribute(
    body,
    "data-local",
    status(dom.read_storage("localStorage", "artifact_test")),
  )
  dom.set_attribute(
    body,
    "data-session",
    status(dom.read_storage("sessionStorage", "artifact_test")),
  )
  dom.set_attribute(
    body,
    "data-indexed",
    status(dom.open_database("artifact_test")),
  )
  dom.set_attribute(
    body,
    "data-parent",
    status(dom.ancestor_document("parent")),
  )
  dom.set_attribute(body, "data-top", status(dom.ancestor_document("top")))
  let assert Ok(fetch) = fetch.get()
  let request = fetch.RequestInit("GET", [], "", None)
  let _ =
    promise.map(
      fetch.send(fetch, "http://127.0.0.1:7201/artifact-leak?fetch", request),
      fn(result) { dom.set_attribute(body, "data-fetch", status(result)) },
    )
  // Removing inner policies cannot remove the fixed policy of the wrapper.
  let assert Ok(metas) = dom.query(dom.document(), "meta")
  list.each(metas, dom.remove)
  let image = dom.create("img")
  dom.set_attribute(image, "src", "http://127.0.0.1:7201/artifact-leak?image")
  dom.append(body, image)
}
