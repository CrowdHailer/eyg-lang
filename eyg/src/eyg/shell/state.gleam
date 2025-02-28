// import eyg/shell/situation.{type Situation}
// import website/sync/browser
// import website/sync/sync
// import eyg/website/components/snippet
// import gleam/javascript/promisex
// import gleam/json
// import gleam/list
// import gleam/option.{type Option}
// import website/harness/browser as harness
// import website/harness/spotless
// import website/harness/spotless/netlify/openapi as netlify_spec
// import lustre/effect
// import morph/editable
// import oas
// import plinth/browser/document
// import plinth/browser/element

// pub type Shell {
//   Shell(
//     config: spotless.Config,
//     situation: Situation,
//     cache: sync.Sync,
//     previous: List(#(Option(snippet.Value), editable.Expression)),
//     display_help: Bool,
//     scope: snippet.Scope,
//     source: snippet.Snippet,
//   )
// }

// fn new_snippet(scope, cache, config, eff) {
//   snippet.active(
//     editable.Vacant,
//     scope,
//     effects(config) |> list.append(eff),
//     cache,
//   )
// }

// pub fn init(config: spotless.Config) {
//   let cache = sync.init(browser.get_origin())

//   let assert Ok(spec) = document.get_element_by_id("netlify.openapi.json")
//   let spec = element.inner_text(spec)
//   let assert Ok(spec) = json.decode(spec, oas.decoder)
//   let eff = netlify_spec.effects_from_oas(spec, config.netlify)

//   let situation = situation.init()
//   let snippet = new_snippet([], cache, config, eff)

//   let state = Shell(config, situation, cache, [], True, [], snippet)

//   #(state, effect.none())
// }

// pub type Message {
//   SyncMessage(sync.Message)
//   SnippetMessage(snippet.Message)
// }

// pub fn effects(config) {
//   list.append(harness.effects(), spotless.effects(config))
// }

// fn dispatch_to_snippet(state, current, promise) {
//   let refs = snippet.references(current)
//   let Shell(cache: cache, ..) = state
//   let #(cache, tasks) = sync.fetch_missing(cache, refs)
//   let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))

//   let state = Shell(..state, cache: cache, source: current)

//   let snippet_effect =
//     effect.from(fn(d) {
//       promisex.aside(promise, fn(message) { d(SnippetMessage(message)) })
//     })
//   #(state, effect.batch([snippet_effect, sync_effect]))
// }

// fn dispatch_nothing(state, current, _promise) {
//   let refs = snippet.references(current)
//   let Shell(cache: cache, ..) = state
//   let #(cache, tasks) = sync.fetch_missing(cache, refs)
//   let eff = effect.from(browser.do_sync(tasks, SyncMessage))

//   let state = Shell(..state, cache: cache, source: current)
//   #(state, eff)
// }

// pub fn update(state: Shell, message) {
//   case message {
//     SyncMessage(message) -> {
//       let cache = sync.task_finish(state.cache, message)
//       let #(cache, tasks) = sync.fetch_all_missing(cache)
//       let snippet = snippet.set_references(state.source, cache)
//       let state = Shell(..state, source: snippet, cache: cache)
//       #(state, effect.from(browser.do_sync(tasks, SyncMessage)))
//     }
//     SnippetMessage(message) -> {
//       let #(current, eff) = snippet.update(state.source, message)
//       case eff {
//         snippet.Nothing -> dispatch_nothing(state, current, Nil)
//         snippet.RunEffect(p) ->
//           dispatch_to_snippet(state, current, snippet.await_running_effect(p))
//         snippet.FocusOnCode ->
//           dispatch_nothing(state, current, snippet.focus_on_buffer())
//         snippet.FocusOnInput ->
//           dispatch_nothing(state, current, snippet.focus_on_input())
//         snippet.ToggleHelp -> {
//           let state = Shell(..state, display_help: !state.display_help)
//           #(state, effect.none())
//         }
//         snippet.MoveAbove -> {
//           case state.previous {
//             [] -> #(state, effect.none())
//             [#(_value, exp), ..] -> {
//               let current =
//                 snippet.active(
//                   exp,
//                   state.scope,
//                   effects(state.config),
//                   state.cache,
//                 )
//               #(Shell(..state, source: current), effect.none())
//             }
//           }
//         }
//         snippet.MoveBelow -> #(state, effect.none())
//         snippet.ReadFromClipboard ->
//           dispatch_to_snippet(state, current, snippet.read_from_clipboard())
//         snippet.WriteToClipboard(text) ->
//           dispatch_to_snippet(state, current, snippet.write_to_clipboard(text))
//         snippet.Conclude(value, effects, scope) -> {
//           let previous = [#(value, snippet.source(current)), ..state.previous]
//           // TODO eff
//           let source = new_snippet(scope, state.cache, state.config, [])
//           let state = Shell(..state, source: source, previous: previous)
//           #(
//             state,
//             effect.from(fn(_d) {
//               snippet.focus_on_buffer()
//               Nil
//             }),
//           )
//         }
//       }
//     }
//   }
// }
