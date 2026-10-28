//// Browser interactions and state transitions are Gleam, sharing the host layout.

import gleam/int
import gleam/javascript/array
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import otel/clock
import plinthx/browser/dom
import plinthx/browser/html
import plinthx/javascript/array as native_array
import tracing/model
import tracing/view

type State {
  State(
    captures: List(model.Capture),
    current: Int,
    active: Bool,
    intrinsics: Bool,
    focus: option.Option(#(Int, Int)),
    zoom: Int,
    sort: String,
    selected: option.Option(String),
  )
}

fn element(document, id) {
  let assert Ok(element) = dom.get_element_by_id(document, id)
  element
}

fn content(document, id, content) {
  let assert Ok(_) = html.set_inner_html(element(document, id), content)
  Nil
}

fn capture(state: State) {
  let assert Ok(capture) =
    state.captures |> list.drop(state.current) |> list.first
  capture
}

fn render(document, state: State) {
  let capture = capture(state)
  content(
    document,
    "chart",
    view.chart(capture, state.active, state.intrinsics, state.focus, state.zoom),
  )
  content(
    document,
    "rows",
    view.bottom_up(capture, state.sort, state.intrinsics),
  )
  let assert Ok(root) = model.root(capture)
  content(
    document,
    "stats",
    "Elapsed: "
      <> view.ms(clock.difference(root.ended, root.started))
      <> " ms · Inside host effects: "
      <> view.ms(model.timing(root, "eyg.profile.effect_ns"))
      <> " ms · Outside host effects: "
      <> view.ms(model.timing(root, "eyg.profile.active_ns"))
      <> " ms · "
      <> int.to_string(list.length(capture.spans))
      <> " spans",
  )
  let details = case state.selected {
    None -> "Choose a frame in the timeline or table."
    Some(id) ->
      case list.find(capture.spans, fn(s) { s.span_id == id }) {
        Ok(s) -> view.details(s)
        Error(_) -> "Frame not found"
      }
  }
  content(document, "detail", details)
  let assert Ok(_) =
    dom.set_attribute(
      element(document, "download"),
      "href",
      capture.id <> ".chrome.json",
    )
  let assert Ok(_) =
    dom.set_attribute(
      element(document, "jaeger"),
      "href",
      "http://localhost:16686/trace/" <> root.trace_id,
    )
  Nil
}

fn update(document, states, change) {
  let assert Ok(state) = array.get(states, 0)
  let state = change(state)
  let assert Ok(_) = native_array.splice(states, 0, 1, [state])
  render(document, state)
}

pub fn main() {
  let assert Ok(document) = dom.get_document()
  let assert Ok(data) = dom.text_content(element(document, "recordings"))
  let assert Ok(captures) = json.parse(data, model.collection("profiles"))
  list.each(captures, fn(capture) {
    assert model.verify(capture.spans) == Ok(Nil)
  })
  case captures {
    [] ->
      content(
        document,
        "chart",
        "No function recordings yet. Run the profile-capture command.",
      )
    _ -> {
      let active = case html.get_location() {
        Ok(location) -> html.hash(location) == "#active"
        Error(_) -> False
      }
      let states =
        array.from_list([
          State(captures, 0, active, False, None, 1, "self", None),
        ])
      let assert Ok(_) =
        html.set_select_value(element(document, "clock"), case active {
          True -> "active"
          False -> "wall"
        })
      let root = element(document, "viewer")
      let assert Ok(_) =
        dom.add_event_listener(root, "change", fn(event) {
          case dom.element_target(event) {
            Error(_) -> Nil
            Ok(target) -> {
              let id = dom.get_attribute(target, "id") |> result.unwrap("")
              update(document, states, fn(state) {
                case id {
                  "recording" ->
                    State(
                      ..state,
                      current: html.select_value(target)
                        |> result.unwrap("0")
                        |> int.parse
                        |> result.unwrap(0),
                      focus: None,
                      selected: None,
                    )
                  "clock" ->
                    State(
                      ..state,
                      active: html.select_value(target) == Ok("active"),
                      focus: None,
                    )
                  "intrinsics" ->
                    State(
                      ..state,
                      intrinsics: html.input_checked(target)
                        |> result.unwrap(False),
                      focus: None,
                    )
                  _ -> state
                }
              })
            }
          }
        })
      let assert Ok(_) =
        dom.add_event_listener(element(document, "zoom"), "input", fn(event) {
          let assert Ok(target) = dom.element_target(event)
          let zoom =
            html.input_value(target)
            |> result.unwrap("1")
            |> int.parse
            |> result.unwrap(1)
          update(document, states, fn(state) { State(..state, zoom:) })
        })
      let assert Ok(_) =
        dom.add_event_listener(root, "click", fn(event) {
          case dom.element_target(event) {
            Error(_) -> Nil
            Ok(target) -> {
              case dom.get_attribute(target, "id") {
                Ok("reset") -> {
                  let assert Ok(_) =
                    html.set_input_value(element(document, "zoom"), "1")
                  update(document, states, fn(state) {
                    State(..state, zoom: 1, focus: None)
                  })
                }
                _ ->
                  case dom.closest(target, "[data-sort]") {
                    Ok(header) -> {
                      let assert Ok(sort) =
                        dom.get_attribute(header, "data-sort")
                      update(document, states, fn(state) {
                        State(..state, sort:)
                      })
                    }
                    Error(_) ->
                      case dom.closest(target, "[data-frame]") {
                        Ok(frame) -> {
                          let assert Ok(id) =
                            dom.get_attribute(frame, "data-frame")
                          // Keep the chart DOM alive so the browser can recognize dblclick.
                          let assert Ok(state) = array.get(states, 0)
                          let assert Ok(_) =
                            native_array.splice(states, 0, 1, [
                              State(..state, selected: Some(id)),
                            ])
                          let assert Ok(span) =
                            list.find(capture(state).spans, fn(s) {
                              s.span_id == id
                            })
                          content(document, "detail", view.details(span))
                        }
                        Error(_) -> Nil
                      }
                  }
              }
            }
          }
        })
      let assert Ok(_) =
        dom.add_event_listener(
          element(document, "chart"),
          "dblclick",
          fn(event) {
            let selected = {
              use target <- result.try(dom.element_target(event))
              use frame <- result.try(
                dom.closest(target, "[data-frame]") |> result.replace_error(Nil),
              )
              dom.get_attribute(frame, "data-frame")
            }
            case selected {
              Error(_) -> Nil
              Ok(id) ->
                update(document, states, fn(state) {
                  let layout =
                    model.layout(capture(state), state.active, state.intrinsics)
                  case
                    list.find(layout.frames, fn(f) { f.span.span_id == id })
                  {
                    Ok(frame) if frame.end > frame.start ->
                      State(..state, focus: Some(#(frame.start, frame.end)))
                    _ -> state
                  }
                })
            }
          },
        )
      let assert Ok(state) = array.get(states, 0)
      render(document, state)
    }
  }
}
