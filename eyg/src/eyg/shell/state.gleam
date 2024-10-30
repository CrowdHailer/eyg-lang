import eyg/shell/situation.{type Situation}
import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import gleam/javascript/promisex
import gleam/list
import gleam/option.{type Option}
import harness/impl/browser as harness
import harness/impl/spotless
import lustre/effect
import morph/editable

pub type Shell {
  Shell(
    config: spotless.Config,
    situation: Situation,
    cache: sync.Sync,
    previous: List(#(Option(snippet.Value), editable.Expression)),
    display_help: Bool,
    scope: snippet.Scope,
    source: snippet.Snippet,
  )
}

fn new_snippet(scope, cache, config) {
  snippet.active(editable.Vacant(""), scope, effects(config), cache)
}

pub fn init(config) {
  let cache = sync.init(browser.get_origin())

  let situation = situation.init()
  let snippet = new_snippet([], cache, config)
  let state = Shell(config, situation, cache, [], True, [], snippet)

  #(state, effect.none())
}

pub type Message {
  SyncMessage(sync.Message)
  SnippetMessage(snippet.Message)
}

pub fn effects(config) {
  list.append(harness.effects(), spotless.effects(config))
}

fn dispatch_to_snippet(state, current, promise) {
  let refs = snippet.references(current)
  let Shell(cache: cache, ..) = state
  let #(cache, tasks) = sync.fetch_missing(cache, refs)
  let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))

  let state = Shell(..state, cache: cache, source: current)

  let snippet_effect =
    effect.from(fn(d) {
      promisex.aside(promise, fn(message) { d(SnippetMessage(message)) })
    })
  #(state, effect.batch([snippet_effect, sync_effect]))
}

fn dispatch_nothing(state, current, _promise) {
  let refs = snippet.references(current)
  let Shell(cache: cache, ..) = state
  let #(cache, tasks) = sync.fetch_missing(cache, refs)
  let eff = effect.from(browser.do_sync(tasks, SyncMessage))

  let state = Shell(..state, cache: cache, source: current)
  #(state, eff)
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
      let #(current, eff) = snippet.update(state.source, message)
      case eff {
        snippet.Nothing -> dispatch_nothing(state, current, Nil)
        snippet.AwaitRunningEffect(p) ->
          dispatch_to_snippet(state, current, snippet.await_running_effect(p))
        snippet.FocusOnCode ->
          dispatch_nothing(state, current, snippet.focus_on_buffer())
        snippet.FocusOnInput ->
          dispatch_nothing(state, current, snippet.focus_on_input())
        snippet.ToggleHelp -> {
          let state = Shell(..state, display_help: !state.display_help)
          #(state, effect.none())
        }
        snippet.MoveAbove -> {
          case state.previous {
            [] -> #(state, effect.none())
            [#(_value, exp), ..] -> {
              let current =
                snippet.active(
                  exp,
                  state.scope,
                  effects(state.config),
                  state.cache,
                )
              #(Shell(..state, source: current), effect.none())
            }
          }
        }
        snippet.MoveBelow -> #(state, effect.none())
        snippet.ReadFromClipboard ->
          dispatch_to_snippet(state, current, snippet.read_from_clipboard())
        snippet.WriteToClipboard(text) ->
          dispatch_to_snippet(state, current, snippet.write_to_clipboard(text))
        snippet.Conclude(value, scope) -> {
          let previous = [#(value, snippet.source(current)), ..state.previous]
          let source = new_snippet(scope, state.cache, state.config)
          let state = Shell(..state, source: source, previous: previous)
          #(
            state,
            effect.from(fn(_d) {
              snippet.focus_on_buffer()
              Nil
            }),
          )
        }
      }
    }
  }
}
