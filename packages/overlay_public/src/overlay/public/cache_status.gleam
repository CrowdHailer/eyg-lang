//// What the page is waiting on the hub for.
////
//// The agent is not told about a module that has not arrived, it is simply
//// not resumed, so this is the only account of a pause in a run of tool
//// calls.

import gleam/list
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import overlay/web/state
import overlay/web/view

pub fn render(model: state.State) -> element.Element(a) {
  case view.waiting_on(model) {
    [] -> element.none()
    waiting -> h.div([a.class("hub-activity")], list.map(waiting, render_one))
  }
}

/// A line is built from the parts it is read in, each one classed by whether
/// it is a reference or the account of what is being done with it.
fn render_one(waiting: view.Waiting) {
  let parts = case waiting {
    view.PullingReleases -> [#("hub-action", "pulling the release log")]
    view.Fetching(reference:) -> [
      #("hub-action", "fetching"),
      #("hub-reference", reference),
    ]
    view.Blocked(reference:, on:) -> [
      #("hub-reference", reference),
      #("hub-action", "depends on"),
      #("hub-reference", on),
    ]
  }

  // A reference is longer than the width of the chat, so the line is
  // truncated and kept whole as the title.
  let description = list.map(parts, fn(part) { part.1 }) |> string.join(" ")
  h.div(
    [a.class("hub-waiting"), a.title(description)],
    list.map(parts, fn(part) {
      let #(class, text) = part
      h.span([a.class(class)], [h.text(text)])
    }),
  )
}
