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

pub fn update(state, message) {
  let State(previous, current) = state
  case message {
    Drafting(d.KeyDown("Enter")) -> {
      case current {
        d.State(zip, d.Navigate) -> {
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
              #(State(previous, d.new(e.Vacant)), effect.none())
            }
          }
        }
        _ -> #(state, effect.none())
      }
    }
    Drafting(m) -> {
      let current = d.handle(current, m)
      #(State(previous, current), effect.none())
    }
  }
}
//       Navigate, "Enter" -> 
