import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/state as istate
import eyg/ir/tree as ir
import gleam/io
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import gleam/set
import morph/analysis
import morph/editable as e
import plinth/javascript/console
import website/components/readonly
import website/components/snippet
import website/mount/interactive
import website/sync/cache

pub type ShellEntry {
  Executed(
    value: Option(analysis.Value),
    // The list of effects are kept in reverse order
    effects: List(interactive.RuntimeEffect),
    source: readonly.Readonly,
  )
}

pub type ShellFailure {
  SnippetFailure(snippet.Failure)
  NoMoreHistory
}

pub type Run {
  // if no type errors then unhandled effect is still running
  Run(
    started: Bool,
    return: interactive.Return,
    effects: List(interactive.RuntimeEffect),
  )
}

pub type Shell {
  Shell(
    failure: Option(ShellFailure),
    previous: List(ShellEntry),
    source: snippet.Snippet,
    // A shell component is not a whole page so it isn't the canonical state of the client
    // It keeps only a reference to the client cache that can be updated as required
    cache: cache.Cache,
    // The derrived properties of a shell are very tightly bound.
    // Typing is based on the scope which is updated by the runtime.
    effects: List(#(String, analysis.EffectSpec)),
    // I need to rebuild because scope is difference and I want expression in example
    scope: interactive.Scope,
    // Evaluated is needed to show what effect will run in the shell console
    // evaluated: interactive.Return,
    // current_effects: List(interactive.RuntimeEffect),
    run: Run,
    // needs a task counter
  )
}

// could just be given a snippet
pub fn init(effects, cache) {
  let source = e.from_annotated(ir.vacant())
  let scope = []
  let snippet =
    snippet.active(source)
    |> snippet_analyse(scope, cache, effects)
  Shell(
    failure: None,
    previous: [],
    source: snippet,
    cache: cache,
    effects: effects,
    scope: scope,
    // what the task would be is derivable
    // evaluated: interactive.evaluate(source, scope, cache),
    // current_effects: [],
    run: Run(False, interactive.evaluate(source, scope, cache), []),
    // mount: mount.init(source, effects, cache),
  )
}

fn close_many_previous(shell_entries) {
  list.map(shell_entries, fn(e) {
    let Executed(a, b, r) = e
    let r = readonly.Readonly(..r, status: readonly.Idle)
    Executed(a, b, r)
  })
}

fn close_all_previous(shell: Shell) {
  let previous = close_many_previous(shell.previous)

  Shell(..shell, previous: previous)
}

pub type Message {
  // Current could be called input
  CacheUpdate(cache.Cache)
  CurrentMessage(snippet.Message)
  ExternalHandlerCompleted(Result(analysis.Value, istate.Debug(analysis.Path)))
  UserClickedPrevious(Int)
}

pub type Effect {
  Nothing
  RunFinished
  RunEffect(value: analysis.Value, handler: analysis.ExternalBlocking)
}

pub fn update(shell, message) {
  case message {
    CacheUpdate(cache) -> {
      let Shell(run: run, ..) = shell
      let run = run_update_cache(run, cache)
      let shell = Shell(..shell, cache:)
      #(shell, Nothing)
    }
    CurrentMessage(message) -> {
      let shell = close_all_previous(shell)
      let shell = case snippet.user_message(message) {
        True -> Shell(..shell, failure: None)
        False -> shell
      }
      // The source must always be updated after handling a message
      let #(source, eff) = snippet.update(shell.source, message)
      let shell = Shell(..shell, source: source)
      case eff {
        snippet.Nothing -> #(shell, Nothing)
        snippet.NewCode -> new_code(shell)
        snippet.Confirm -> confirm(shell)
        snippet.Failed(failure) -> #(
          Shell(..shell, failure: Some(SnippetFailure(failure))),
          Nothing,
        )
        // TODO need to handle focusing on code by returning two effects or not actually have it at this level
        snippet.FocusOnCode -> new_code(shell)
        snippet.FocusOnInput -> #(shell, {
          // TODO need to have effect
          // snippet.focus_on_input()
          Nothing
        })
        snippet.ToggleHelp -> #(shell, Nothing)
        snippet.MoveAbove -> {
          case shell.previous {
            [] -> #(Shell(..shell, failure: Some(NoMoreHistory)), Nothing)
            [Executed(source:, ..), ..] -> set_code(shell, source.source)
          }
        }
        snippet.MoveBelow -> #(shell, Nothing)
        snippet.ReadFromClipboard -> #(
          shell,
          todo as "clipboard",
          // Some(snippet.read_from_clipboard()),
        )
        snippet.WriteToClipboard(text) -> #(
          shell,
          todo as "clipboard",
          // Some(snippet.write_to_clipboard(text)),
        )
      }
    }
    ExternalHandlerCompleted(result) -> {
      // Some/None on further effects
      let #(run, task) = handle_external(shell, result)
      let shell = Shell(..shell, run:)
      case task {
        Some(#(lift, handler)) -> #(shell, RunEffect(lift, handler))
        None ->
          case run.return {
            Ok(#(value, scope)) -> {
              let record =
                Executed(
                  value,
                  run.effects,
                  readonly.new(shell.source.editable),
                )
              let previous = [record, ..shell.previous]
              Shell(..shell, previous:, scope:)
              |> set_code(e.from_annotated(ir.vacant()))
            }

            Error(_) -> todo as "leave and show error"
          }
      }
    }
    UserClickedPrevious(index) -> {
      // Don't keep analysis in history as the scope will change, which is the main reason to rerun a snippet
      let Shell(previous:, ..) = shell
      case listx.at(previous, index) {
        Ok(Executed(source:, ..)) -> set_code(shell, source.source)
        Error(Nil) -> #(shell, Nothing)
      }
    }
  }
}

fn set_code(shell, code) {
  let shell = Shell(..shell, source: snippet.active(code))
  new_code(shell)
}

// The snippet will have cleared it's analysis
fn new_code(shell) {
  let Shell(source:, scope:, cache:, ..) = shell
  let run = new_run(source.editable, scope, cache)

  let source = snippet_analyse(source, scope, cache, shell.effects)
  #(Shell(..shell, source:, run:), Nothing)
}

fn confirm(shell) {
  let Shell(source:, cache:, effects: extrinsic, run:, ..) = shell
  let Run(started:, return:, effects:) = run
  // TODO add extrinsic or external field to the shell or a context
  case started, return {
    False, Ok(#(value, scope)) -> {
      let record = Executed(value, effects, readonly.new(source.editable))
      let previous = [record, ..shell.previous]
      Shell(..shell, previous:, scope:)
      |> set_code(e.from_annotated(ir.vacant()))
    }
    False, Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
      case list.key_find(extrinsic, label) {
        Ok(#(_lift, _reply, blocking)) -> {
          let run = Run(..run, started: True)
          let shell = Shell(..shell, run:)
          #(shell, RunEffect(lift, blocking))
        }
        _ -> #(shell, Nothing)
      }
    }
    _, _ -> #(shell, Nothing)
  }
}

// analyse stuff

// this is not just configurable for the reload case
fn snippet_analyse(snippet, scope, cache, effect_specs) {
  let snippet.Snippet(editable:, ..) = snippet
  let analysis =
    interactive.do_analysis(
      editable,
      scope,
      cache,
      interactive.effect_types(effect_specs),
    )
  snippet.Snippet(..snippet, analysis: Some(analysis))
}

// runner stuff

fn new_run(editable, scope, cache) {
  Run(False, interactive.evaluate(editable, scope, cache), [])
}

fn run_update_cache(run, cache) {
  let Run(started:, return:, ..) = run
  let return = cache.run(return, cache, block.resume)
  // Do effects should be a thing
  todo
}

fn handle_external(shell, result) {
  let Shell(run:, cache:, ..) = shell
  // TODO need to pair up with a run number
  let Run(return:, effects:, ..) = run
  case return {
    Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
      let run = case result {
        Ok(reply) -> {
          let effects = [
            interactive.RuntimeEffect(label, lift, reply),
            ..effects
          ]
          let return =
            cache.run(block.resume(reply, env, k), cache, block.resume)
          let action = case lookup_external(return, shell.effects) {
            Ok(#(lift, blocking)) -> Some(#(lift, blocking))
            Error(Nil) -> None
          }

          #(Run(True, return, effects), action)
        }
        Error(reason) -> #(Run(False, Error(reason), effects), None)
      }
    }
    _ -> todo
  }
}

fn lookup_external(return, extrinsic) {
  case return {
    Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
      case list.key_find(extrinsic, label) {
        Ok(#(_lift, _reply, blocking)) -> Ok(#(lift, blocking))
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

// -----

pub fn message_from_previous_code(shell: Shell, m, i) {
  let assert Ok(#(pre, executed, post)) = listx.split_around(shell.previous, i)
  let pre = close_many_previous(pre)
  let post = close_many_previous(post)
  let Executed(a, b, r) = executed
  let #(r, action) = readonly.update(r, m)
  let previous = listx.gather_around(pre, Executed(a, b, r), post)
  let effect = case action {
    readonly.Nothing -> None
    readonly.Fail(message) -> {
      console.warn(message)
      None
    }
    readonly.MoveAbove -> None
    readonly.MoveBelow -> None
    readonly.WriteToClipboard(text) -> Some(readonly.write_to_clipboard(text))
  }
  let shell = Shell(..shell, previous: previous)
  #(shell, effect)
}
