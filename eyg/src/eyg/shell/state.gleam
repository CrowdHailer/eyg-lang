import eyg/analysis/inference/levels_j/contextual as j
import eyg/runtime/interpreter/state as istate
import eyg/runtime/value as v
import eyg/shell/situation.{type Situation}
import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import eyg/website/run
import gleam/io
import gleam/listx
import gleam/option.{type Option, None, Some}
import harness/impl/browser as harness
import harness/impl/spotless
import lustre/effect
import morph/editable

type Path =
  Nil

type Value =
  v.Value(Path, #(List(#(istate.Kontinue(Path), Path)), istate.Env(Path)))

type Scope =
  List(#(String, Value))

pub type Shell {
  Shell(
    situation: Situation,
    cache: sync.Sync,
    previous: List(#(Option(Value), editable.Expression)),
    display_help: Bool,
    scope: Scope,
    source: snippet.Snippet,
  )
}

// Done is a signal we can work with here. Remove the runner.
const scratch_ref = "heae72a60"

fn new_snippet(cache) {
  snippet.init(editable.Vacant(""), harness.effects(), cache)
}

pub fn init(_) {
  let cache = sync.init(browser.get_origin())
  // let #(cache, tasks) = sync.fetch_missing(cache, [scratch_ref])

  let situation = situation.init()
  let snippet = new_snippet(cache)
  let state = Shell(situation, cache, [], True, [], snippet)

  #(state, effect.none())
}

pub type Message {
  SyncMessage(sync.Message)
  SnippetMessage(snippet.Message)
  // Interrupt
}

pub fn effects() {
  spotless.effects()
}

fn effect_types() {
  listx.value_map(effects(), fn(details) { #(details.0, details.1) })
}

pub fn update(state: Shell, message) {
  let effects = effect_types()
  case message {
    SyncMessage(message) -> {
      let cache = sync.task_finish(state.cache, message)
      let #(cache, tasks) = sync.fetch_all_missing(cache)
      let snippet = snippet.set_references(state.source, cache)
      let state = Shell(..state, source: snippet, cache: cache)
      #(state, effect.from(browser.do_sync(tasks, SyncMessage)))
    }
    SnippetMessage(message) -> {
      let #(sn, eff) = snippet.update(state.source, message)
      let #(cache, tasks) = sync.fetch_all_missing(state.cache)
      let state = Shell(..state, cache: cache)
      case snippet.key_error(sn) {
        Some("?") -> {
          let state = Shell(..state, display_help: !state.display_help)
          #(state, effect.none())
        }
        // Some("ArrowUp")
        //           b.Command(Some(b.ActionFailed("move up"))), True, [], _ -> {
        //             case state.previous {
        //               [] -> #(state, effect.none())
        //               [#(_value, expression), ..] -> {
        //                 let buffer = b.from(p.focus_at(expression, []))
        //                 let state = Shell(..state, buffer: buffer)
        //                 #(state, effect.none())
        //               }
        //             }
        //           }
        Some("Enter") -> {
          let run = snippet.run(sn)
          let run.Run(status, effects) = run
          case status {
            run.Done(value, scope) -> {
              io.debug(listx.keys(scope))
              io.debug("add effects")
              let previous = [#(value, snippet.source(sn)), ..state.previous]
              let source = new_snippet(state.cache)
              let state = Shell(..state, source: source, previous: previous)
              #(state, effect.none())
            }
            _ -> #(state, effect.none())
          }
        }
        _ -> {
          let state = Shell(..state, source: sn)
          #(state, case eff {
            None -> {
              effect.from(browser.do_sync(tasks, SyncMessage))
            }
            Some(f) ->
              effect.from(fn(d) {
                let d = fn(m) { d(SnippetMessage(m)) }
                f(d)
              })
          })
        }
      }
    }
  }
}
