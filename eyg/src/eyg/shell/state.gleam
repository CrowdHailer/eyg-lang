import drafting/view/utilities
import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/isomorphic
import eyg/runtime/break
import eyg/runtime/interpreter/block as r
import eyg/runtime/interpreter/state as istate
import eyg/runtime/value as v
import eyg/shell/buffer as b
import eyg/shell/situation.{type Situation}
import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import eyg/website/run
import eygir/annotated as a
import gleam/dict
import gleam/dynamic
import gleam/dynamicx
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import harness/impl/browser as harness
import harness/impl/spotless
import harness/stdlib
import lustre/effect
import morph/analysis
import morph/editable
import morph/projection as p

type Path =
  Nil

type Value =
  v.Value(Path, #(List(#(istate.Kontinue(Path), Path)), istate.Env(Path)))

type Scope =
  #(List(#(String, Value)), j.Env)

pub type Shell {
  Shell(
    situation: Situation,
    cache: sync.Sync,
    previous: List(#(Option(Value), editable.Expression)),
    display_help: Bool,
    scope: Option(Scope),
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
  let state = Shell(situation, cache, [], True, None, snippet)

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
      let #(snippet, eff) = snippet.update(state.source, message)
      let #(cache, tasks) = sync.fetch_all_missing(state.cache)
      let state = Shell(..state, cache: cache)
      case snippet.key_error(snippet) {
        Some("?") -> {
          let state = Shell(..state, display_help: !state.display_help)
          #(state, effect.none())
        }
        Some("Enter") -> {
          let run = snippet.run(snippet)
          let run.Run(status, effects) = run
          case status {
            run.Done(value, _value) -> {
              io.debug("add effects")
              let previous = [
                #(value, snippet.source(snippet)),
                ..state.previous
              ]
              let source = new_snippet(state.cache)
              let state = Shell(..state, source: source, previous: previous)
              #(state, effect.none())
            }
            _ -> #(state, effect.none())
          }
        }
        _ -> {
          let state = Shell(..state, source: snippet)
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
    //   Buffer(message) -> {
    //     let Shell(cache: cache, scope: scope, runner: run, buffer: buffer, ..) =
    //       state
    //     case run {
    //       Some(Run(Handling(_, _, _, _), _)) -> #(state, effect.none())
    //       None | Some(Run(Failed(_), _)) -> {
    //         let context =
    //           analysis.Context(
    //             // bindings are empty as long as everything is properly poly
    //             bindings: dict.new(),
    //             scope: case scope {
    //               Some(#(_env, tenv)) -> tenv
    //               None -> []
    //             },
    //             references: sync.types(cache),
    //             builtins: j.builtins(),
    //           )
    //         let buffer = b.update(buffer, message, context, effects)
    //         utilities.update_focus()
    //         let references = b.references(buffer)

    //         let #(source, mode) = buffer
    //         case mode, p.blank(source), sync.missing(cache, references), scope {
    //           b.Command(Some(b.NoKeyBinding("Enter"))), False, [], Some(scope) -> {
    //             let #(env, _tenv) = scope
    //             let expression = editable.to_annotated(p.rebuild(source), [])
    //             execute(expression, env, sync.values(cache))
    //             |> handle_execution([], scope, state)
    //           }
    //           b.Command(Some(b.NoKeyBinding("Enter"))), False, _, _ -> {
    //             let buffer = #(source, b.Command(Some(b.ActionFailed("run"))))
    //             #(Shell(..state, buffer: buffer), effect.none())
    //           }
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
    //           _, _, _missing, _ -> {
    //             let #(cache, tasks) = sync.fetch_missing(cache, references)
    //             #(
    //               Shell(..state, cache: cache, buffer: buffer, runner: None),
    //               effect.from(browser.do_sync(tasks, SyncMessage)),
    //             )
    //           }
    //         }
    //       }
    //     }
    //   }
    //   Executor(Reply(reply)) -> {
    //     let Shell(scope: scope, runner: run, ..) = state
    //     let assert Some(scope) = scope
    //     let assert Some(Run(Handling(label, lift, env, k), effects)) = run
    //     let effects = [#(label, #(lift, reply)), ..effects]

    //     r.resume(reply, env, k)
    //     |> handle_execution(effects, scope, state)
    //   }
    //   Interrupt -> {
    //     let state = Shell(..state, runner: None)
    //     #(state, effect.none())
    //   }
  }
}
// fn handle_execution(result, effects, scope, state) {
//   let Shell(buffer: buffer, previous: previous, cache: cache, ..) = state
//   let #(source, _mode) = buffer
//   let #(_env, tenv) = scope
//   case result {
//     Ok(#(value, env)) -> {
//       let previous = [#(value, p.rebuild(source)), ..previous]
//       let context =
//         analysis.Context(
//           // bindings are empty as long as everything is properly poly
//           bindings: dict.new(),
//           scope: tenv,
//           references: sync.types(cache),
//           builtins: j.builtins(),
//         )
//       // let eff =
//       //   effects
//       //   |> list.fold(isomorphic.Empty, fn(acc, new) {
//       //     let #(label, #(lift, reply)) = new
//       //     isomorphic.EffectExtend(label, #(lift, reply), acc)
//       //   })
//       let tenv = b.final_scope(source, context, isomorphic.Empty)
//       let scope = Some(#(env, tenv))
//       let run = None
//       let buffer = b.empty()
//       let state =
//         Shell(
//           ..state,
//           buffer: buffer,
//           runner: run,
//           scope: scope,
//           previous: previous,
//         )
//       #(state, effect.none())
//     }
//     Error(debug) -> {
//       let #(suspend, effect) = handle_extrinsic_effects(debug)
//       let run = Some(Run(suspend, effects))
//       let state = Shell(..state, runner: run)
//       #(state, effect)
//     }
//   }
// }
