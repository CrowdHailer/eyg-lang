import gleam/dict
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import gleam/string
import gleam/javascript/array
import gleam/javascript/promise
import plinth/browser/window
import plinth/browser/file_system
import plinth/browser/file
import euclidean/square
import lustre/effect
import eygir/decode
import eygir/annotated as a
import morph/editable as e
import morph/projection
import eyg/runtime/value as v
import eyg/runtime/interpreter/runner as r
import eyg/runtime/break as fail
import harness/stdlib
import drafting/session as d
import drafting/bindings
import eyg/runtime/cast
import harness/ffi/core
import harness/effect as impl
import spotless/repl/loader
import spotless/file_system as fs

pub type Executing {
  Running
  Failed(String)
  Ready
}

pub type State {
  State(
    previous: List(#(v.Value(Nil, Nil), e.Expression)),
    current: d.Session,
    executing: Executing,
  )
}

pub fn init(_) {
  loader.load("")
  let current = d.new(bindings.default(), e.Vacant)
  #(State([], current, Ready), effect.none())
}

pub type Message {
  Drafting(d.Message)
  Complete(Result(v.Value(Nil, Nil), String))
}

// TODO move somewhere REPL probably
pub fn handlers() {
  dict.new()
  |> dict.insert("Alert", impl.window_alert().2)
  |> dict.insert("Await", impl.await().2)
  |> dict.insert("File_Read", fs.file_read)
  |> dict.insert("Load", fn(_) {
    let p =
      promise.map(do_load(), fn(r) {
        case r {
          Ok(exp) -> v.ok(v.LinkedList(core.expression_to_language(exp)))
          Error(reason) -> v.error(v.Str(reason))
        }
      })

    Ok(v.Promise(p))
  })
  |> dict.insert("Open", fn(url) {
    use url <- try(cast.as_string(url))
    let space = #(
      window.outer_width(window.self()),
      window.outer_height(window.self()),
    )
    let frame = #(600, 700)
    let #(#(offset_x, offset_y), #(inner_x, inner_y)) =
      square.center(frame, space)
    let features =
      string.concat([
        "popup",
        ",width=",
        int.to_string(inner_x),
        ",height=",
        int.to_string(inner_y),
        ",left=",
        int.to_string(offset_x),
        ",top=",
        int.to_string(offset_y),
      ])

    let assert Ok(popup) = window.open(url, "_blank", features)
    Ok(v.unit)
  })
}

pub fn update(state, message) {
  let State(previous, current, executing) = state
  case message, executing {
    Drafting(d.KeyDown("Enter")), Ready -> {
      case current {
        d.Session(_, zip, d.Navigate) -> {
          let state = State(..state, executing: Running)
          #(
            state,
            effect.from(fn(d) {
              let editable = projection.rebuild(zip)
              let source = e.to_expression(editable)
              let source = a.add_annotation(source, Nil)
              promise.map(
                r.await(r.execute(source, stdlib.env(), handlers())),
                fn(result) {
                  let result = case result {
                    Ok(value) -> {
                      let value = dynamic.unsafe_coerce(dynamic.from(value))
                      Ok(value)
                    }
                    Error(#(reason, _, _, _)) -> {
                      Error(fail.reason_to_string(reason))
                    }
                  }
                  d(Complete(result))
                },
              )

              Nil
            }),
          )
        }
        _ -> #(state, effect.none())
      }
    }
    Drafting(m), Ready | Drafting(m), Failed(_) -> {
      case d.handle(current, m) {
        Ok(current) -> #(State(previous, current, Ready), effect.none())
        Error(Nil) -> {
          io.debug(#(current, m))
          #(State(previous, current, Ready), effect.none())
        }
      }
    }
    Complete(result), Running -> {
      case result {
        Ok(value) -> {
          let current = current.projection
          let editable = projection.rebuild(current)
          let previous = [#(value, editable), ..previous]
          #(
            State(previous, d.new(bindings.default(), e.Vacant), Ready),
            effect.none(),
          )
        }
        Error(reason) -> {
          #(State(previous, current, Failed(reason)), effect.none())
        }
      }
    }
    _, _ -> #(state, effect.none())
  }
}

//       Navigate, "Enter" ->

fn do_load() {
  use file_handles <- promise.try_await(file_system.show_open_file_picker())
  let assert [file_handle] = array.to_list(file_handles)
  use file <- promise.try_await(file_system.get_file(file_handle))
  use text <- promise.map(file.text(file))
  use source <- try(
    decode.from_json(text)
    |> result.map_error(fn(e) { string.inspect(e) }),
  )
  let source = a.add_annotation(source, Nil)
  Ok(source)
  // Ok(e.from_annotated(source))
}
