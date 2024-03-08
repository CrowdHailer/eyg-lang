import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/effect
import plinth/browser/document
import plinth/browser/element
import plinth/browser/window
import morph/editable as e
import morph/projection
import morph/navigation
import morph/transformation

pub type Action =
  #(String, fn(projection.Projection) -> State, Option(String))

pub type Mode {
  Navigate
  Pallet(search: String, suggestions: List(Action), offset: Int)
  RequireString(String, fn(String) -> projection.Projection)
}

pub type State {
  State(zip: projection.Projection, mode: Mode)
}

pub fn new(source) {
  State(projection.focus_at(source, [], []), Navigate)
}

pub fn init(_) {
  let source = e.Vacant
  #(new(source), effect.none())
}

pub type Message {
  KeyDown(String)
  // Update input handles all focused overlays
  UpdateInput(String)
  Do(fn(projection.Projection) -> State)
  DoIt
}

fn actions() {
  [
    #(
      "insert mode",
      fn(zip) {
        let Ok(#(value, rebuild)) = projection.text(zip)
        State(zip, RequireString(value, rebuild))
      },
      Some("i"),
    ),
    #(
      "delete",
      fn(zip) {
        let zip = transformation.delete(zip)
        State(zip, Navigate)
      },
      Some("d"),
    ),
    #(
      "variable",
      fn(zip) {
        let rebuild = transformation.variable(zip)
        update_focus()
        State(zip, RequireString("", rebuild))
      },
      Some("v"),
    ),
    #(
      "function",
      fn(zip) {
        let rebuild = transformation.function(zip)
        update_focus()
        State(zip, RequireString("", rebuild))
      },
      Some("f"),
    ),
    #(
      "call function",
      fn(zip) {
        let zip = transformation.call(zip)
        State(zip, Navigate)
      },
      Some("c"),
    ),
    #(
      "let",
      fn(zip) {
        let rebuild = transformation.assign(zip)
        update_focus()
        State(zip, RequireString("", fn(label) { rebuild(e.Bind(label)) }))
      },
      Some("e"),
    ),
    #("let above", fn(zip) { todo }, None),
    #(
      "string",
      fn(zip) {
        let #(value, rebuild) = transformation.string(zip)
        State(zip, RequireString(value, rebuild))
      },
      Some("\""),
    ),
    #(
      "list",
      fn(zip) {
        let zip = transformation.list(zip)
        State(zip, Navigate)
      },
      Some("l"),
    ),
    #(
      "extend list",
      fn(zip) {
        case transformation.extend_list(zip) {
          transformation.NeedString(rebuild) ->
            State(zip, RequireString("", rebuild))
          transformation.NoString(zip) -> State(zip, Navigate)
        }
      },
      Some(","),
    ),
    #(
      "spread list",
      fn(zip) {
        let zip = transformation.spread_list(zip)
        State(zip, Navigate)
      },
      Some("."),
    ),
    #(
      "record",
      fn(zip) {
        case transformation.record(zip) {
          transformation.NeedString(rebuild) ->
            State(zip, RequireString("", rebuild))
          transformation.NoString(zip) -> State(zip, Navigate)
        }
      },
      Some("r"),
    ),
    #(
      "overwrite",
      fn(zip) {
        let rebuild = transformation.overwrite(zip)
        update_focus()
        State(zip, RequireString("", fn(label) { rebuild(label) }))
      },
      Some("o"),
    ),
    #(
      "tag",
      fn(zip) {
        let rebuild = transformation.tag(zip)
        update_focus()
        State(zip, RequireString("", fn(label) { rebuild(label) }))
      },
      Some("t"),
    ),
    #(
      "match",
      fn(zip) {
        let zip = transformation.match(zip)
        update_focus()
        State(zip, Navigate)
      },
      Some("m"),
    ),
    #(
      "open match",
      fn(zip) {
        let zip = transformation.open_match(zip)
        update_focus()
        State(zip, Navigate)
      },
      Some("M"),
    ),
    #(
      "builtin",
      fn(zip) {
        let #(value, rebuild) = transformation.builtin(zip)
        State(zip, RequireString(value, rebuild))
      },
      Some("j"),
    ),
  ]
  // TODO require text
  // let rebuild = transformation.line_above(zip)
  // State(zip, RequireString("", fn(label) { rebuild(e.Bind(label)) }))
  // "call as argument",
}

fn update_focus() {
  window.request_animation_frame(fn() {
    case document.query_selector("#focus-input") {
      Ok(el) -> {
        element.focus(el)
      }
      _ -> {
        let assert Ok(el) = document.query_selector("#code")
        element.focus(el)
      }
    }
  })
}

fn scroll_to() {
  window.request_animation_frame(fn() {
    case document.query_selector("#highlighted") {
      Ok(el) -> {
        element.scroll_into_view(el)
      }
      _ -> {
        io.debug(document.query_selector_all("#highlighted"))
        io.debug("didn't find element")
        Nil
      }
    }
  })
}

pub fn handle(state, message) {
  let State(mode: mode, zip: zip) = state
  case message {
    KeyDown(k) -> {
      let state = case mode, k {
        Navigate, " " -> {
          update_focus()
          State(..state, mode: Pallet("", actions(), 0))
        }
        Navigate, "a" -> {
          scroll_to()
          State(navigation.increase(zip), mode)
        }
        Navigate, "s" -> {
          scroll_to()
          State(navigation.decrease(zip), mode)
        }
        Navigate, "ArrowUp" -> {
          scroll_to()
          State(navigation.move_up(zip), mode)
        }
        Navigate, "ArrowDown" -> {
          scroll_to()
          State(navigation.move_down(zip), mode)
        }
        Navigate, "ArrowLeft" -> {
          scroll_to()
          State(navigation.move_left(zip), mode)
        }
        Navigate, "ArrowRight" -> {
          scroll_to()
          State(navigation.move_right(zip), mode)
        }
        _, "Enter" -> state
        _, "Escape" -> State(..state, mode: Navigate)
        Navigate, other -> {
          let result =
            list.find_map(actions(), fn(a) {
              case a {
                #(_, do, Some(k)) if k == other -> Ok(do)
                _ -> Error(Nil)
              }
            })
          case result {
            Ok(do) -> {
              update_focus()
              do(zip)
            }
            Error(Nil) -> state
          }
        }

        RequireString(_, _), _ -> state
        Pallet(search, actions, index), "ArrowUp" ->
          State(..state, mode: move_selection(search, actions, index, -1))
        Pallet(search, actions, index), "ArrowDown" ->
          State(..state, mode: move_selection(search, actions, index, 1))
        // let go till submit
        a, b -> {
          io.debug(#(a, b))
          panic as "bad hanle"
        }
      }
    }
    UpdateInput(value) -> update_input(state, value)
    Do(action) -> {
      update_focus()

      action(zip)
    }
    DoIt -> {
      update_focus()
      let assert RequireString(value, rebuild) = mode
      State(rebuild(value), Navigate)
    }
  }
}

pub fn update(state, message) {
  #(handle(state, message), effect.none())
}

fn update_input(state, value) {
  let State(mode: mode, ..) = state
  case mode {
    Pallet(_, actions, index) -> {
      State(..state, mode: Pallet(value, actions, index))
    }
    RequireString(_, rebuild) ->
      State(..state, mode: RequireString(value, rebuild))
  }
}

fn move_selection(search, actions, index, change) {
  let new = index + change
  let index = case 0 <= new && new < list.length(actions) {
    True -> new
    False -> index
  }
  Pallet(search, actions, index)
}
