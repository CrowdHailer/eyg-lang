import drafting/view/picker
import drafting/view/utilities
import eyg/runtime/break as fail
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eyg/shell/buffer
import gleam/dynamic
import gleam/dynamicx
import gleam/io
import gleam/javascript/promise
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
  Buffer(buffer.Message)
  Loaded(projection.Projection)
  Complete(Result(Next, String))
  Interrupt
  CopiedToClipboard(Result(Nil, String))
}

pub fn update(state, message) {
  utilities.update_focus()
  let State(previous, env, context, current, executing) = state
  case message, executing {
    Buffer(buffer.KeyDown("Enter")), Editing(buffer.Command(_)) -> {
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
              dynamicx.unsafe_coerce(dynamic.from(env)),
              capabilities.handlers(),
            )),
            fn(result) {
              let result = case result {
                Ok(value) -> {
                  let value = dynamicx.unsafe_coerce(dynamic.from(value))
                  Ok(Value(value))
                }
                Error(#(fail.UnhandledEffect("Prompt", prompt), _, env, k)) ->
                  Ok(Env(dynamicx.unsafe_coerce(dynamic.from(env))))
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
    Buffer(buffer.KeyDown("ArrowUp")), Editing(buffer.Command(_)) -> {
      case state.previous, projection.blank(state.current) {
        [#(_, expression), ..], True -> {
          let state =
            State(..state, current: projection.focus_at(expression, []))
          #(state, effect.none())
        }
        _, _ -> #(state, effect.none())
      }
    }
    Buffer(buffer.KeyDown("q")), Editing(buffer.Command(_)) -> {
      todo as "copy doesn't exist in buffer, this shouldn't as no effects"
      // #(state, effect.from(buffer.copy(current, CopiedToClipboard)))
    }

    Buffer(buffer.KeyDown("Q")), Editing(buffer.Command(_)) -> {
      // let task = fn(d) {
      //   use result <- promisex.aside(buffer.paste(current))
      //   case result {
      //     Ok(current) -> d(Loaded(current))
      //     Error(reason) -> todo as "failed to paste"
      //   }
      // }
      #(state, effect.from(todo))
    }
    // TODO remove separate Buffer have key focus only on item
    Buffer(buffer.KeyDown(key)), Failed(_) -> {
      let #(source, mode) =
        buffer.handle_keydown(key, context, current, buffer.Command(None), [])
      let state = State(..state, current: source, executing: Editing(mode))
      #(state, effect.none())
    }
    Buffer(buffer.KeyDown(key)), Editing(mode) -> {
      let #(source, mode) =
        buffer.handle_keydown(key, context, current, mode, [])
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
    Interrupt, _ -> {
      // TODO needs a way to reach into the promise that is running
      let state = State(..state, executing: Editing(buffer.Command(None)))
      #(state, effect.none())
    }
    Loaded(new), _ -> {
      let state = State(..state, current: new)
      #(state, effect.none())
    }
    Buffer(buffer.UpdatePicker(picker.Updated(picker))),
      Editing(buffer.Pick(_, rebuild))
    -> {
      let mode = buffer.Pick(picker, rebuild)
      let state = State(..state, executing: Editing(mode))
      #(state, effect.none())
    }
    Buffer(buffer.UpdatePicker(picker.Decided(value))),
      Editing(buffer.Pick(_, rebuild))
    -> {
      let mode = buffer.Command(None)
      let state =
        State(..state, current: rebuild(value), executing: Editing(mode))
      #(state, effect.none())
    }
    Buffer(buffer.UpdatePicker(picker.Dismissed)),
      Editing(buffer.Pick(_, _rebuild))
    -> {
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

pub fn weather_example() {
  let source =
    e.Block(
      [
        #(
          e.Bind("location"),
          e.Case(
            e.Call(e.Perform("Await"), [
              e.Call(e.Perform("Geo"), [e.Record([], None)]),
            ]),
            [
              #("Ok", e.Function([e.Bind("location")], e.Variable("location"))),
              #(
                "Error",
                e.Function(
                  [e.Bind("_")],
                  e.Call(e.Perform("Abort"), [
                    e.String("failed to get location"),
                  ]),
                ),
              ),
            ],
            None,
          ),
        ),
        #(e.Bind("_"), e.Call(e.Perform("Alert"), [e.String("my location")])),
      ],
      e.Vacant("s"),
      True,
    )

  projection.focus_at(source, [0, 1])
}

pub fn netliy_sites_example() {
  let source =
    e.Block(
      [
        #(
          e.Bind("sites"),
          e.Case(
            e.Call(e.Perform("Await"), [
              e.Call(e.Perform("Netlify.Sites"), [e.Record([], None)]),
            ]),
            [
              #("Ok", e.Function([e.Bind("sites")], e.Variable("sites"))),
              #(
                "Error",
                e.Function(
                  [e.Bind("_")],
                  e.Call(e.Perform("Abort"), [e.String("failed to get sites")]),
                ),
              ),
            ],
            None,
          ),
        ),
      ],
      e.Call(e.Select(e.Select(e.Variable("std"), "list"), "map"), [
        e.Variable("sites"),
        e.Function(
          [e.Destructure([#("name", "name"), #("url", "url")])],
          e.Record(
            [#("name", e.Variable("name")), #("url", e.Variable("url"))],
            None,
          ),
        ),
      ]),
      True,
    )

  projection.focus_at(source, [1])
}

pub fn wordcount_example() {
  let source =
    e.Block(
      [
        #(
          e.Bind("content"),
          e.Case(
            e.Call(e.Perform("Await"), [
              e.Call(e.Perform("Netlify.Sites"), [e.Record([], None)]),
            ]),
            [
              #("Ok", e.Function([e.Bind("sites")], e.Variable("sites"))),
              #(
                "Error",
                e.Function(
                  [e.Bind("_")],
                  e.Call(e.Perform("Abort"), [e.String("failed to get sites")]),
                ),
              ),
            ],
            None,
          ),
        ),
      ],
      e.Call(e.Select(e.Select(e.Variable("std"), "list"), "map"), [
        e.Variable("sites"),
        e.Function(
          [e.Destructure([#("name", "name"), #("url", "url")])],
          e.Record(
            [#("name", e.Variable("name")), #("url", e.Variable("url"))],
            None,
          ),
        ),
      ]),
      True,
    )

  projection.focus_at(source, [1])
}
