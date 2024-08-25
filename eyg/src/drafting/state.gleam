import drafting/view/utilities
import eyg/analysis/inference/levels_j/contextual as j
import eyg/runtime/break
import eyg/runtime/cast
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import eyg/shell/buffer
import eyg/sync/browser
import eyg/sync/fragment
import eyg/sync/sync
import eygir/decode
import eygir/expression
import gleam/dict
import gleam/dictx
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/javascript/promisex
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/effect
import morph/analysis
import morph/editable as e
import morph/projection as p
import plinth/browser/clipboard
import plinth/javascript/console
import snag.{type Snag}

pub type State {
  State(
    cache: sync.Sync,
    buffer: buffer.Buffer,
    analysis: Option(analysis.Analysis),
    failure: Result(Nil, String),
    show_help: Bool,
    auto_analyse: Bool,
  )
}

pub fn init(_) {
  let cache = sync.init(browser.get_origin())
  let state = State(cache, buffer.empty(), None, Ok(Nil), True, True)
  #(state, effect.none())
}

pub type Message {
  Synced(reference: String, value: Result(expression.Expression, Snag))
  Buffer(buffer.Message)
  Loading(Promise(Result(e.Expression, String)))
  Loaded(Result(p.Projection, String))
  Copied(Result(Nil, String))
}

pub fn copy(buffer, then) {
  fn(dispatch) {
    use result <- promisex.aside(case buffer.focus_to_json(buffer) {
      Ok(data) -> clipboard.write_text(data)

      Error(reason) -> promise.resolve(Error(reason))
    })
    dispatch(then(result))
  }
}

pub fn paste(buffer, then) {
  fn(dispatch) {
    use result <- promisex.aside(clipboard.read_text())
    let return = case result {
      Ok(text) ->
        case decode.from_json(text) {
          Ok(expression) ->
            case buffer.insert_some(buffer, e.from_expression(expression)) {
              Ok(#(proj, _)) -> Ok(proj)
              Error(reason) -> Error(reason)
            }

          Error(reason) -> Error(string.inspect(reason))
        }
      Error(reason) -> Error(reason)
    }
    dispatch(then(return))
  }
}

pub fn update(state, message) {
  case message {
    Synced(ref, result) -> {
      let State(cache: cache, buffer: buffer, ..) = state
      let cache = sync.task_finish(cache, ref, result)
      let references = buffer.references(buffer)
      let #(cache, tasks) = sync.fetch_missing(cache, references)
      let state = State(..state, cache: cache, buffer: buffer)
      #(state, effect.from(browser.do_sync(tasks, Synced)))
    }
    Buffer(message) -> {
      utilities.update_focus()
      let State(cache: cache, buffer: buffer, ..) = state
      let context =
        analysis.Context(
          // bindings are empty as long as everything is properly poly
          bindings: dict.new(),
          scope: [],
          references: sync.types(cache),
          builtins: j.builtins(),
        )
      // probably best to pass around analysis
      let buffer = buffer.update(buffer, message, context, [])
      case buffer.1 {
        buffer.Command(Some(buffer.NoKeyBinding(k)))
          if k == "Shift" || k == "Alt" || k == "Control"
        -> {
          #(state, effect.none())
        }
        buffer.Command(Some(buffer.NoKeyBinding("Enter"))) -> {
          // TODO auto analyse look at shell branch
          let state =
            State(
              ..state,
              analysis: Some(analysis.analyse(state.buffer.0, context)),
            )
          #(state, effect.none())
        }
        buffer.Command(Some(buffer.NoKeyBinding("?"))) -> {
          let state = State(..state, show_help: !state.show_help)
          #(state, effect.none())
        }
        buffer.Command(Some(buffer.NoKeyBinding("q"))) -> {
          #(state, effect.from(copy(buffer, Copied)))
        }
        buffer.Command(Some(buffer.NoKeyBinding("Q"))) -> {
          #(state, effect.from(paste(buffer, Loaded)))
        }
        buffer.Command(Some(buffer.NoKeyBinding("x"))) -> {
          let exp = e.to_annotated(p.rebuild(buffer.0), [])
          io.debug("gatherin values")
          let values = sync.values(cache)
          io.debug("evaling")
          // fragment.eval(exp, values)
          let env = fragment.empty_env(values)
          let handlers =
            dictx.singleton("Log", fn(message) {
              use message <- result.then(cast.as_string(message))
              console.log(message)
              Ok(v.unit)
            })
          case r.execute(exp, env, handlers) {
            Ok(value) -> console.log(value)
            Error(#(break.UnhandledEffect("Abort", v.Str(message)), _, _, _)) ->
              console.log(message)
            Error(#(reason, _, _, _)) -> console.log(reason)
          }
          #(state, effect.none())
        }
        buffer.Command(None) -> {
          let State(cache: cache, ..) = state
          let references = buffer.references(buffer)
          let #(cache, tasks) = sync.fetch_missing(cache, references)
          let state = State(..state, cache: cache, buffer: buffer)
          #(state, effect.from(browser.do_sync(tasks, Synced)))
        }
        _ -> #(State(..state, buffer: buffer), effect.none())
      }
    }
    Loading(task) -> #(
      state,
      effect.from(fn(d) {
        promise.map(task, fn(r) {
          case r {
            Ok(editable) -> d(Loaded(Ok(p.focus_at(editable, []))))
            Error(reason) -> d(Loaded(Error(reason)))
          }
        })
        Nil
      }),
    )
    Loaded(result) -> {
      case result {
        Ok(source) -> {
          let buffer = buffer.from(source)
          let State(cache: cache, ..) = state
          let references = buffer.references(buffer)
          let #(cache, tasks) = sync.fetch_missing(cache, references)
          let state = State(..state, cache: cache, buffer: buffer)
          #(state, effect.from(browser.do_sync(tasks, Synced)))
        }
        Error(reason) -> {
          let state = State(..state, failure: Error(reason))
          #(state, effect.none())
        }
      }
    }
    Copied(result) -> {
      let state = State(..state, failure: result)
      #(state, effect.none())
    }
  }
}
