import eyg/shell/situation.{type Situation}
import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import eyg/website/run
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import harness/impl/browser as harness
import harness/impl/spotless
import lustre/effect
import morph/editable

pub type Shell {
  Shell(
    situation: Situation,
    cache: sync.Sync,
    previous: List(#(Option(snippet.Value), editable.Expression)),
    display_help: Bool,
    scope: snippet.Scope,
    source: snippet.Snippet,
  )
}

fn new_snippet(scope, cache) {
  snippet.init(editable.Vacant(""), scope, effects(), cache)
}

pub fn init(_) {
  let cache = sync.init(browser.get_origin())

  let situation = situation.init()
  let snippet = new_snippet([], cache)
  let state = Shell(situation, cache, [], True, [], snippet)

  #(state, effect.none())
}

pub type Message {
  SyncMessage(sync.Message)
  SnippetMessage(snippet.Message)
  // Interrupt
}

pub fn effects() {
  list.append(harness.effects(), spotless.effects())
}

pub fn update(state: Shell, message) {
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
          let run.Run(status, _effects) = run
          case status {
            run.Done(value, scope) -> {
              io.debug("add effects")
              let previous = [#(value, snippet.source(sn)), ..state.previous]
              let source = new_snippet(scope, state.cache)
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
