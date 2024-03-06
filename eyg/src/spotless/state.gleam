import gleam/dict
import gleam/dynamic
import gleam/io
import gleam/list
import gleam/option.{None}
import lustre/effect
import plinth/browser/document
import plinth/browser/element
import plinth/browser/window
import eygir/annotated as a
import morph/editable as e
import morph/transform
import morph/action
import eyg/runtime/value as v
import eyg/runtime/interpreter/runner as r
import harness/stdlib

pub type Action =
  #(String, fn(transform.Zip) -> #(transform.Zip, Mode))

pub type Mode {
  Navigate
  Pallet(search: String, suggestions: List(Action), offset: Int)
  RequireString(String, fn(String) -> transform.Zip)
}

pub type State {
  State(
    previous: List(#(v.Value(Nil, Nil), e.Expression)),
    zip: transform.Zip,
    mode: Mode,
  )
}

pub fn init(_) {
  let source = e.Vacant
  let zip = transform.focus_at(source, [], [])
  #(State([], zip, Navigate), effect.none())
}

pub type Message {
  KeyDown(String)
  // Update input handles all focused overlays
  UpdateInput(String)
  Do(fn(transform.Zip) -> #(transform.Zip, Mode))
  DoIt
  //   TextInput(String)
}

//   TextChange(String)
//   ApplyChange

fn actions() {
  [
    #("delete", fn(zip) {
      let zip = action.delete(zip)
      #(zip, Navigate)
    }),
    #("function", fn(zip) {
      let rebuild = action.function(zip)
      update_focus()
      #(zip, RequireString("", rebuild))
    }),
    #("call function", fn(zip) {
      let zip = action.call(zip)
      #(zip, Navigate)
    }),
    #("let", fn(zip) {
      let rebuild = action.assign(zip)
      update_focus()
      #(zip, RequireString("", fn(label) { rebuild(e.Bind(label)) }))
    }),
    #("let above", fn(zip) { todo }),
    #("list", fn(zip) {
      let zip = action.list(zip)
      #(zip, Navigate)
    }),
    #("tag", fn(zip) {
      let rebuild = action.tag(zip)
      update_focus()
      #(zip, RequireString("", fn(label) { rebuild(label) }))
    }),
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

// TODO reuse update code from drafting
pub fn update(state, message) {
  let State(previous, zip, mode) = state
  case message {
    KeyDown(k) -> {
      let state = case mode, k {
        Navigate, " " -> {
          update_focus()
          #(State(..state, mode: Pallet("", actions(), 0)), effect.none())
        }
        Navigate, "a" -> #(
          State(previous, action.increase(zip), mode),
          effect.none(),
        )
        Navigate, "s" -> #(
          State(previous, action.decrease(zip), mode),
          effect.none(),
        )
        Navigate, "ArrowUp" -> #(
          State(previous, action.move_up(zip), mode),
          effect.none(),
        )
        Navigate, "ArrowDown" -> #(
          State(previous, action.move_down(zip), mode),
          effect.none(),
        )
        Navigate, "ArrowLeft" -> #(
          State(previous, action.move_left(zip), mode),
          effect.none(),
        )
        Navigate, "ArrowRight" -> #(
          State(previous, action.move_right(zip), mode),
          effect.none(),
        )
        Navigate, "Enter" -> {
          let editable = transform.rebuild(zip)
          io.debug(editable)
          let source = e.to_expression(editable)
          io.debug(source)
          let source = a.add_annotation(source, Nil)
          let result = r.execute(source, stdlib.env(), dict.new())
          case result {
            Ok(value) -> {
              let value = dynamic.unsafe_coerce(dynamic.from(value))
              let previous = [#(value, editable), ..previous]
              let source = e.Vacant
              let zip = transform.focus_at(source, [], [])
              #(State(previous, zip, Navigate), effect.none())
            }
          }
          // io.debug(result)
          // panic as "running"
        }
        Navigate, other -> {
          io.debug(other)
          panic
        }

        RequireString(_, _), _ -> #(state, effect.none())
        Pallet(search, actions, index), "ArrowUp" -> #(
          State(..state, mode: move_selection(search, actions, index, -1)),
          effect.none(),
        )
        Pallet(search, actions, index), "ArrowDown" -> #(
          State(..state, mode: move_selection(search, actions, index, 1)),
          effect.none(),
        )
      }
    }
    UpdateInput(value) -> update_input(state, value)
    Do(action) -> {
      update_focus()
      let #(zip, mode) = action(zip)

      #(State(..state, zip: zip, mode: mode), effect.none())
    }
    DoIt -> {
      update_focus()
      let assert RequireString(value, rebuild) = mode
      #(State(previous, rebuild(value), Navigate), effect.none())
    }
  }
  //     TextInput(content) -> #(State(..state, content: content), effect.none())
  //         "e" -> {
  //           let rebuild = action.assign(state.zip)
  //           let rebuild = fn(new) { rebuild(e.Bind(new)) }
  //           State(..state, mode: Insert("", rebuild))
  //         }
  //         "i" ->
  //           case transform.text(state.zip) {
  //             Ok(#(text, apply)) -> State(..state, mode: Insert(text, apply))
  //           }
  //         "p" -> {
  //           let apply = action.perform(state.zip)
  //           State(..state, mode: Insert("", apply))
  //         }
  //         "f" -> {
  //           let rebuild = action.function(state.zip)
  //           State(..state, mode: Insert("", rebuild))
  //         }
  //         _ -> {
  //           let zip = action.apply_key(k, state.zip)
  //           State(..state, zip: zip)
  //         }
  //       }
  //     TextChange(n) -> {
  //       let assert Insert(_, apply) = state.mode
  //       let mode = Insert(n, apply)
  //       let state = State(..state, mode: mode)
  //       #(state, effect.none())
  //     }
  //     ApplyChange -> {
  //       let assert Insert(v, apply) = state.mode
  //       let state = State(..state, mode: Command, zip: apply(v))
  //       #(state, effect.none())
}

fn update_input(state, value) {
  let State(mode: mode, ..) = state
  case mode {
    Pallet(_, actions, index) -> {
      #(State(..state, mode: Pallet(value, actions, index)), effect.none())
    }
    RequireString(_, rebuild) -> #(
      State(..state, mode: RequireString(value, rebuild)),
      effect.none(),
    )
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
