import gleam/dict
import gleam/dynamic
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/javascript/array
import gleam/javascript/promise
import plinth/browser/file_system
import plinth/browser/file
import lustre/effect
import eygir/decode
import eygir/annotated as a
import morph/editable as e
import morph/transform
import eyg/runtime/value as v
import eyg/runtime/interpreter/runner as r
import eyg/runtime/break as fail
import harness/stdlib
import drafting/state as d

pub type State {
  State(
    previous: List(#(v.Value(Nil, Nil), e.Expression)),
    current: d.State,
    error: Option(String),
  )
}

pub fn init(_) {
  let current = d.new(e.Vacant)
  #(State([], current, None), effect.none())
}

pub type Message {
  Drafting(d.Message)
  LoadSource
  SourceLoaded(e.Expression)
}

pub fn update(state, message) {
  let State(previous, current, _error) = state
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
              #(State(previous, d.new(e.Vacant), None), effect.none())
            }
            Error(#(reason, _, _, _)) -> {
              #(
                State(previous, current, Some(fail.reason_to_string(reason))),
                effect.none(),
              )
            }
          }
        }
        _ -> #(state, effect.none())
      }
    }
    Drafting(m) -> {
      let current = d.handle(current, m)
      #(State(previous, current, None), effect.none())
    }
    LoadSource -> {
      #(
        state,
        effect.from(fn(d) {
          promise.try_await(file_system.show_open_file_picker(), fn(
            file_handles,
          ) {
            let assert [file_handle] = array.to_list(file_handles)
            use file <- promise.try_await(file_system.get_file(file_handle))
            use text <- promise.map(file.text(file))
            let assert Ok(source) = decode.from_json(text)
            let source = a.add_annotation(source, Nil)
            let source = e.from_annotated(source)
            io.debug("done")
            d(SourceLoaded(source))
            Ok(Nil)
          })

          Nil
        }),
      )
    }
    SourceLoaded(source) -> {
      let current = d.new(source)
      #(State(state.previous, current, None), effect.none())
    }
  }
}
//       Navigate, "Enter" ->
