import gleam/dict
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
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
import eyg/runtime/capture
import eyg/runtime/interpreter/state
import harness/ffi/core
import harness/effect as impl
import spotless/file_system as fs
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug as tdebug

pub type Executing {
  Running
  Failed(String)
  Ready
}

pub type State {
  State(
    previous: List(#(v.Value(Nil, Nil), e.Expression)),
    env: state.Env(Nil),
    current: d.Session,
    executing: Executing,
  )
}

pub fn init(initial) {
  // k will exit the program
  let #(_, env, k) = initial
  let current = d.new(bindings.default(), e.Vacant)
  #(State([], env, current, Ready), effect.none())
}

pub type Message {
  Drafting(d.Message)
  Complete(Result(v.Value(Nil, Nil), String))
  JumpTo(List(Int))
}

// TODO move somewhere, a directory called REPL might be a good place to group these capabilities
pub fn handler_type() {
  let state = infer.new_state()
  let eff = t.Empty
  let eff = t.EffectExtend("Alert", #(t.String, t.unit), eff)
  let eff = t.EffectExtend("Load", #(t.unit, t.unit), eff)
  let eff = t.EffectExtend("Delay", #(t.Integer, t.Promise(t.unit)), eff)
  io.debug(state)
  let level = 0
  let #(var, state) = binding.mono(level, state)
  let eff = t.EffectExtend("Await", #(t.Promise(var), var), eff)
  #(eff, state)
}

pub fn handlers() {
  dict.new()
  |> dict.insert("Alert", impl.window_alert().2)
  |> dict.insert("Await", impl.await().2)
  |> dict.insert("Delay", impl.wait().2)
  |> dict.insert("File_Read", fs.file_read)
  |> dict.insert("Choose", impl.choose().2)
  |> dict.insert("HTTP", impl.http().2)
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

fn value_to_type(value) {
  // case value {
  //   v.Closure(x,)
  //   v.Binary(_) -> t.Binary
  //   v.Integer(_) -> t.Integer
  //   v.Str(_) -> t.String
  //   v.LinkedList([]) -> t.List(t.Var(0))
  //   v.LinkedList([item, ..]) -> t.List(value_to_type(item))
  //   v.Record(_) -> panic as "type record"
  //   v.Tagged(label, value) ->
  //     t.Union(t.RowExtend(label, value_to_type(value), t.Var(0)))
  //   v.Partial(_,_) -> panic as "type partial"
  //   v.Promise(_) -> panic as "do promises need to be specific type"
  // }
  // let #(#(_, #(_, t, _, _)), bindings) =
  //   capture.capture(value)
  //   |> infer.infer(t.Empty, 0, infer.new_state())
  // binding.gen(t, 0, bindings)
  t.Var(#(True, 0))
}

// TODO add a small initial script BUT i want std lib etc
// Vars together for environment

fn env_to_type(env: state.Env(Nil)) -> List(#(String, binding.Poly)) {
  env.scope
  |> list.map(fn(pair) {
    let #(var, value) = pair
    #(var, value_to_type(value))
  })
}

pub fn vars_from_env(env: state.Env(Nil)) {
  env.scope
  |> list.map(fn(pair) {
    let #(var, value) = pair
    var
  })
}

pub fn type_errors(projection, env) {
  let env = env_to_type(env)
  let editable = projection.rebuild(projection)
  let source = e.to_expression(editable)
  let #(eff, state) = handler_type()
  let #(_bindings, _, _, tree) = infer.do_infer(source, env, eff, 0, state)
  let #(_, types) = a.strip_annotation(tree)
  let #(_, paths) = a.strip_annotation(e.to_annotated(editable, []))
  let pairs = list.zip(paths, types)
  list.filter_map(pairs, fn(r) {
    let #(rev, #(r, _, _, _)) = r
    case r {
      Ok(_) -> Error(Nil)
      Error(reason) -> Ok(#(list.reverse(rev), reason))
    }
  })
  |> list.map(fn(pair) {
    let #(path, reason) = pair
    #(path, tdebug.render_reason(reason))
  })
}

pub fn fail_message(reason) {
  case reason {
    d.NoKeyBinding(key) ->
      string.concat(["No action bound for key '", key, "'"])
    d.ActionFailed -> "Action not possible at this position"
  }
}

pub fn update(state, message) {
  let State(previous, env, current, executing) = state
  case message, executing {
    Drafting(d.KeyDown("Enter")), Ready -> {
      case current {
        // matches navigate
        d.Session(_, zip, d.Navigate) -> {
          let state = State(..state, executing: Running)
          #(
            state,
            effect.from(fn(d) {
              let editable = projection.rebuild(zip)
              let source = e.to_annotated(editable, [])
              // let source = a.add_annotation(source, Nil)
              promise.map(
                r.await(r.execute(
                  source,
                  dynamic.unsafe_coerce(dynamic.from(env)),
                  handlers(),
                )),
                fn(result) {
                  let result = case result {
                    Ok(value) -> {
                      let value = dynamic.unsafe_coerce(dynamic.from(value))
                      Ok(value)
                    }
                    Error(#(reason, m, _, _)) -> {
                      io.debug(m)
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
      case d.handle(current, m, fn() { vars_from_env(env) }) {
        Ok(current) -> #(
          State(..state, current: current, executing: Ready),
          effect.none(),
        )
        Error(reason) -> {
          let message = fail_message(reason)
          #(
            State(..state, current: current, executing: Failed(message)),
            effect.none(),
          )
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
            State(previous, env, d.new(bindings.default(), e.Vacant), Ready),
            effect.none(),
          )
        }
        Error(reason) -> {
          #(State(previous, env, current, Failed(reason)), effect.none())
        }
      }
    }
    JumpTo(path), _ -> {
      let editable = projection.rebuild(current.projection)
      let projection = projection.focus_at(editable, path, [])
      let session =
        d.Session(..current, projection: projection, mode: d.Navigate)
      let state = State(..state, current: session)
      #(state, effect.none())
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
