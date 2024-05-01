import drafting/state as buffer
import drafting/view/picker
import drafting/view/utilities
import eyg/runtime/break as fail
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import gleam/dynamic
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/option.{type Option, None, Some}
import lustre/effect
import morph/analysis
import morph/editable as e
import morph/projection
import spotless/repl/capabilities

pub type Executing {
  Running
  Failed(String)
  Editing(buffer.Mode)
}

pub type State {
  State(
    previous: List(#(Option(v.Value(Nil, Nil)), e.Expression)),
    // env is runtime context 
    env: state.Env(Nil),
    // context is typing context
    context: analysis.Context,
    current: projection.Projection,
    executing: Executing,
  )
}

pub fn init(initial) {
  // running k will exit the program and can be used for cleanup
  let #(_, env, _k) = initial
  let context = analysis.within_environment(env)
  let source = projection.focus_at(e.Vacant(""), [])
  #(
    State([], env, context, source, Editing(buffer.Command(None))),
    effect.none(),
  )
}

pub type Next {
  Value(v.Value(Nil, Nil))
  Env(state.Env(Nil))
}

pub type Message {
  KeyDown(String)
  Buffer(buffer.Message)
  Loaded(projection.Projection)
  UpdatePicker(picker.Message)
  Complete(Result(Next, String))
  Interrupt
  JumpTo(List(Int))
}

pub fn update(state, message) {
  utilities.update_focus()
  let State(previous, env, context, current, executing) = state
  case message, executing {
    KeyDown("Enter"), Editing(buffer.Command(_)) -> {
      let state = State(..state, executing: Running)
      #(
        state,
        effect.from(fn(d) {
          let editable = projection.rebuild(current)
          let editable = case editable {
            e.Block(assigns, e.Vacant(_), open) ->
              e.Block(
                assigns,
                e.Call(e.Perform("Prompt"), [e.String("")]),
                open,
              )
            other -> other
          }
          let source = e.to_annotated(editable, [])
          promise.map(
            r.await(r.execute(
              source,
              dynamic.unsafe_coerce(dynamic.from(env)),
              capabilities.handlers(),
            )),
            fn(result) {
              let result = case result {
                Ok(value) -> {
                  let value = dynamic.unsafe_coerce(dynamic.from(value))
                  Ok(Value(value))
                }
                Error(#(fail.UnhandledEffect("Prompt", prompt), _, env, k)) ->
                  Ok(Env(dynamic.unsafe_coerce(dynamic.from(env))))
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
    KeyDown("q"), Editing(buffer.Command(_)) -> {
      let task = fn(d) {
        use result <- promisex.aside(buffer.copy(current))
        case result {
          Ok(Nil) -> Nil
          Error(reason) -> {
            io.debug(reason)
            Nil
          }
        }
      }
      #(state, effect.from(task))
    }

    KeyDown("Q"), Editing(buffer.Command(_)) -> {
      let task = fn(d) {
        use result <- promisex.aside(buffer.paste(current))
        case result {
          Ok(current) -> d(Loaded(current))
          Error(reason) -> todo as "failed to paste"
        }
      }
      #(state, effect.from(task))
    }
    // TODO remove separate Buffer have key focus only on item
    KeyDown(key), Failed(_) | Buffer(buffer.KeyDown(key)), Failed(_) -> {
      let #(source, mode) =
        buffer.handle_keydown(key, context, current, buffer.Command(None))
      let state = State(..state, current: source, executing: Editing(mode))
      #(state, effect.none())
    }
    KeyDown(key), Editing(mode) | Buffer(buffer.KeyDown(key)), Editing(mode) -> {
      let #(source, mode) = buffer.handle_keydown(key, context, current, mode)
      let state = State(..state, current: source, executing: Editing(mode))
      #(state, effect.none())
    }
    Buffer(buffer.Submit), Editing(mode) -> {
      let state = case buffer.handle_submit(mode) {
        Ok(#(source, mode)) -> {
          State(..state, current: source, executing: Editing(mode))
        }
        Error(Nil) -> state
      }
      #(state, effect.none())
    }
    Buffer(buffer.UpdateInput(new)), Editing(mode) -> {
      let mode = buffer.handle_input(mode, new)
      let state = State(..state, executing: Editing(mode))
      #(state, effect.none())
    }
    Complete(result), Running -> {
      case result {
        Ok(Value(value)) -> {
          let editable = projection.rebuild(current)
          let previous = [#(Some(value), editable), ..previous]
          #(
            State(
              previous,
              env,
              context,
              projection.focus_at(e.Vacant(""), []),
              Editing(buffer.Command(None)),
            ),
            effect.none(),
          )
        }
        Ok(Env(env)) -> {
          let editable = projection.rebuild(current)
          let previous = [#(None, editable), ..previous]
          let context = analysis.within_environment(env)

          #(
            State(
              previous,
              env,
              context,
              projection.focus_at(e.Vacant(""), []),
              Editing(buffer.Command(None)),
            ),
            effect.none(),
          )
        }
        Error(reason) -> {
          #(
            State(previous, env, context, current, Failed(reason)),
            effect.none(),
          )
        }
      }
    }
    JumpTo(path), _ -> {
      let editable = projection.rebuild(current)
      let source = projection.focus_at(editable, path)
      let state =
        State(
          ..state,
          current: source,
          executing: Editing(buffer.Command(None)),
        )
      #(state, effect.none())
    }
    Interrupt, _ -> {
      // TODO needs a way to reach into the promise that is running
      let state = State(..state, executing: Editing(buffer.Command(None)))
      #(state, effect.none())
    }
    Loaded(new), _ -> {
      let state = State(..state, current: new)
      #(state, effect.none())
    }
    UpdatePicker(picker.Updated(picker)), Editing(buffer.Pick(_, rebuild)) -> {
      let mode = buffer.Pick(picker, rebuild)
      let state = State(..state, executing: Editing(mode))
      #(state, effect.none())
    }
    UpdatePicker(picker.Decided(value)), Editing(buffer.Pick(_, rebuild)) -> {
      let mode = buffer.Command(None)
      let state =
        State(..state, current: rebuild(value), executing: Editing(mode))
      #(state, effect.none())
    }
    UpdatePicker(picker.Dismissed), Editing(buffer.Pick(_, _rebuild)) -> {
      let mode = buffer.Command(None)
      let state = State(..state, executing: Editing(mode))
      #(state, effect.none())
    }
    _, _ -> {
      io.debug(#(message, executing, "misssed"))
      #(state, effect.none())
    }
  }
}
