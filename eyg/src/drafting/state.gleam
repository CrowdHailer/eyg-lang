import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/effect
import plinth/browser/document
import plinth/browser/element
import plinth/browser/window
import morph/editable as e
import morph/transform
import morph/action

pub type Action =
  #(String, fn(transform.Zip) -> State, Option(String))

pub type Mode {
  Navigate
  Pallet(search: String, suggestions: List(Action), offset: Int)
  RequireString(String, fn(String) -> transform.Zip)
}

pub type State {
  State(zip: transform.Zip, mode: Mode)
}

pub fn new(source) {
  State(transform.focus_at(source, [], []), Navigate)
}

pub fn init(_) {
  let source = e.Vacant
  #(new(source), effect.none())
}

pub type Message {
  KeyDown(String)
  // Update input handles all focused overlays
  UpdateInput(String)
  Do(fn(transform.Zip) -> State)
  DoIt
}

fn actions() {
  [
    #(
      "insert mode",
      fn(zip) {
        let Ok(#(value, rebuild)) = transform.text(zip)
        State(zip, RequireString(value, rebuild))
      },
      Some("i"),
    ),
    #(
      "delete",
      fn(zip) {
        let zip = action.delete(zip)
        State(zip, Navigate)
      },
      Some("d"),
    ),
    #(
      "variable",
      fn(zip) {
        let rebuild = action.variable(zip)
        update_focus()
        State(zip, RequireString("", rebuild))
      },
      Some("v"),
    ),
    #(
      "function",
      fn(zip) {
        let rebuild = action.function(zip)
        update_focus()
        State(zip, RequireString("", rebuild))
      },
      Some("f"),
    ),
    #(
      "call function",
      fn(zip) {
        let zip = action.call(zip)
        State(zip, Navigate)
      },
      Some("c"),
    ),
    #(
      "let",
      fn(zip) {
        let rebuild = action.assign(zip)
        update_focus()
        State(zip, RequireString("", fn(label) { rebuild(e.Bind(label)) }))
      },
      Some("e"),
    ),
    #("let above", fn(zip) { todo }, None),
    #(
      "string",
      fn(zip) {
        let #(value, rebuild) = action.string(zip)
        State(zip, RequireString(value, rebuild))
      },
      Some("\""),
    ),
    #(
      "list",
      fn(zip) {
        let zip = action.list(zip)
        State(zip, Navigate)
      },
      Some("l"),
    ),
    #(
      "extend list",
      fn(zip) {
        let zip = action.extend_list(zip)
        State(zip, Navigate)
      },
      Some(","),
    ),
    #(
      "spread list",
      fn(zip) {
        let zip = action.spread_list(zip)
        State(zip, Navigate)
      },
      Some("."),
    ),
    #(
      "record",
      fn(zip) {
        case action.record(zip) {
          action.NeedString(rebuild) -> State(zip, RequireString("", rebuild))
          action.NoString(zip) -> State(zip, Navigate)
        }
      },
      Some("r"),
    ),
    #(
      "tag",
      fn(zip) {
        let rebuild = action.tag(zip)
        update_focus()
        State(zip, RequireString("", fn(label) { rebuild(label) }))
      },
      Some("t"),
    ),
    #(
      "match",
      fn(zip) {
        let zip = action.match(zip)
        update_focus()
        State(zip, Navigate)
      },
      Some("m"),
    ),
    #(
      "open match",
      fn(zip) {
        let zip = action.open_match(zip)
        update_focus()
        State(zip, Navigate)
      },
      Some("M"),
    ),
    #(
      "builtin",
      fn(zip) {
        let #(value, rebuild) = action.builtin(zip)
        State(zip, RequireString(value, rebuild))
      },
      Some("j"),
    ),
  ]
  // TODO require text
  // let rebuild = action.line_above(zip)
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

pub fn handle(state, message) {
  let State(mode: mode, zip: zip) = state
  case message {
    KeyDown(k) -> {
      let state = case mode, k {
        Navigate, " " -> {
          update_focus()
          State(..state, mode: Pallet("", actions(), 0))
        }
        Navigate, "a" -> State(action.increase(zip), mode)
        Navigate, "s" -> State(action.decrease(zip), mode)
        Navigate, "ArrowUp" -> State(action.move_up(zip), mode)
        Navigate, "ArrowDown" -> State(action.move_down(zip), mode)
        Navigate, "ArrowLeft" -> State(action.move_left(zip), mode)
        Navigate, "ArrowRight" -> State(action.move_right(zip), mode)
        _, "Enter" -> state
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
