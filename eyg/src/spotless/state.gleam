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
import drafting/state as d

pub type State {
  State(previous: List(#(v.Value(Nil, Nil), e.Expression)), current: d.State)
}

pub fn init(_) {
  let current = d.new(e.Vacant)
  #(State([], current), effect.none())
}

pub type Message {
  Drafting(d.Message)
}

// KeyDown(String)
// // Update input handles all focused overlays
// UpdateInput(String)
// Do(fn(transform.Zip) -> #(transform.Zip, Mode))
// DoIt
//   TextInput(String)

//   TextChange(String)
//   ApplyChange

// TODO reuse update code from drafting
pub fn update(state, message) {
  let State(previous, current) = state
  case message {
    Drafting(m) -> {
      let current = d.handle(current, m)
      #(State(previous, current), effect.none())
    }
  }
  // case message {
  //   KeyDown(k) -> {
  //     let state = case mode, k {
  //       Navigate, " " -> {
  //         update_focus()
  //         #(State(..state, mode: Pallet("", actions(), 0)), effect.none())
  //       }
  //       Navigate, "a" -> #(
  //         State(previous, action.increase(zip), mode),
  //         effect.none(),
  //       )
  //       Navigate, "s" -> #(
  //         State(previous, action.decrease(zip), mode),
  //         effect.none(),
  //       )
  //       Navigate, "ArrowUp" -> #(
  //         State(previous, action.move_up(zip), mode),
  //         effect.none(),
  //       )
  //       Navigate, "ArrowDown" -> #(
  //         State(previous, action.move_down(zip), mode),
  //         effect.none(),
  //       )
  //       Navigate, "ArrowLeft" -> #(
  //         State(previous, action.move_left(zip), mode),
  //         effect.none(),
  //       )
  //       Navigate, "ArrowRight" -> #(
  //         State(previous, action.move_right(zip), mode),
  //         effect.none(),
  //       )
  //       Navigate, "Enter" -> {
  //         let editable = transform.rebuild(zip)
  //         io.debug(editable)
  //         let source = e.to_expression(editable)
  //         io.debug(source)
  //         let source = a.add_annotation(source, Nil)
  //         let result = r.execute(source, stdlib.env(), dict.new())
  //         case result {
  //           Ok(value) -> {
  //             let value = dynamic.unsafe_coerce(dynamic.from(value))
  //             let previous = [#(value, editable), ..previous]
  //             let source = e.Vacant
  //             let zip = transform.focus_at(source, [], [])
  //             #(State(previous, zip, Navigate), effect.none())
  //           }
  //         }
  //         // io.debug(result)
  //         // panic as "running"
  //       }
  //       Navigate, other -> {
  //         io.debug(other)
  //         panic
  //       }

  //       RequireString(_, _), _ -> #(state, effect.none())
  //       Pallet(search, actions, index), "ArrowUp" -> #(
  //         State(..state, mode: move_selection(search, actions, index, -1)),
  //         effect.none(),
  //       )
  //       Pallet(search, actions, index), "ArrowDown" -> #(
  //         State(..state, mode: move_selection(search, actions, index, 1)),
  //         effect.none(),
  //       )
  //     }
  //   }
  //   UpdateInput(value) -> update_input(state, value)
  //   Do(action) -> {
  //     update_focus()
  //     let #(zip, mode) = action(zip)

  //     #(State(..state, zip: zip, mode: mode), effect.none())
  //   }
  //   DoIt -> {
  //     update_focus()
  //     let assert RequireString(value, rebuild) = mode
  //     #(State(previous, rebuild(value), Navigate), effect.none())
  //   }
  // }
}
