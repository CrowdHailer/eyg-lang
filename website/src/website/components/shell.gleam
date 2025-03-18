import eyg/analysis/type_/binding
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/state as istate
import eyg/ir/tree as ir
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import morph/analysis
import morph/editable as e
import plinth/browser/clipboard
import plinth/javascript/console
import website/components/readonly
import website/components/runner
import website/components/snippet
import website/sync/cache

pub type ShellEntry {
  Executed(
    value: Option(analysis.Value),
    // The list of effects are kept in reverse order
    effects: List(runner.Effect(Nil)),
    source: readonly.Readonly,
  )
}

pub type ShellFailure {
  SnippetFailure(snippet.Failure)
  NoMoreHistory
}

pub type Scope(m) =
  List(#(String, istate.Value(m)))

pub type Return(m) =
  Result(#(Option(istate.Value(m)), Scope(m)), istate.Debug(m))

pub type Run {
  // if no type errors then unhandled effect is still running
  Run(started: Bool, return: Return(Nil), effects: List(runner.Effect(Nil)))
}

pub type Shell {
  Shell(
    // TODO remove failure as it should be at the page level
    failure: Option(ShellFailure),
    previous: List(ShellEntry),
    source: snippet.Snippet,
    // A shell component is not a whole page so it isn't the canonical state of the client
    // It keeps only a reference to the client cache that can be updated as required
    cache: cache.Cache,
    // The derrived properties of a shell are very tightly bound.
    // Typing is based on the scope which is updated by the runtime.
    effect_handlers: List(#(String, runner.Handler(Nil))),
    effect_types: List(#(String, #(binding.Mono, binding.Mono))),
    // I need to rebuild because scope is difference and I want expression in example
    scope: Scope(Nil),
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
  let #(effect_types, effect_handlers) = listx.key_unzip(effects)
  let snippet =
    snippet.active(source)
    |> snippet_analyse(scope, cache, effect_types)
  Shell(
    failure: None,
    previous: [],
    source: snippet,
    cache: cache,
    effect_handlers:,
    effect_types:,
    scope: scope,
    // what the task would be is derivable
    // evaluated: interactive.evaluate(source, scope, cache),
    // current_effects: [],
    run: Run(False, evaluate(source, scope, cache), []),
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
  // The shell can be used in a variety of location where setting the input is desirable
  // On the editor page examples can be chosen to execute in the shell
  ParentSetSource(e.Expression)
  CacheUpdate(cache.Cache)
  // Current could be called input
  CurrentMessage(snippet.Message)
  ExternalHandlerCompleted(Result(analysis.Value, istate.Reason(analysis.Path)))
  UserClickedPrevious(Int)
}

pub type Effect {
  Nothing
  FocusOnCode
  FocusOnInput
  RunExternalHandler(id: Int, thunk: runner.Thunk(Nil))

  ReadFromClipboard
  WriteToClipboard(text: String)
}

pub fn update(shell, message) {
  case message {
    ParentSetSource(source) -> set_code(shell, source)
    CacheUpdate(cache) -> {
      let Shell(run:, effect_handlers:, ..) = shell
      let #(run, action) = run_update_cache(run, cache, effect_handlers)
      case run {
        Run(True, Ok(#(value, scope)), effects) ->
          finalize(shell, value, scope, effects)
        _ -> {
          let shell = Shell(..shell, cache:, run:)
          #(shell, action)
        }
      }
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
        snippet.ReturnToCode -> new_code(shell)
        snippet.FocusOnInput -> #(shell, FocusOnInput)
        snippet.ToggleHelp -> #(shell, Nothing)
        snippet.MoveAbove -> {
          case shell.previous {
            [] -> #(Shell(..shell, failure: Some(NoMoreHistory)), Nothing)
            [Executed(source:, ..), ..] -> set_code(shell, source.source)
          }
        }
        snippet.MoveBelow -> #(shell, Nothing)
        snippet.ReadFromClipboard -> #(shell, ReadFromClipboard)
        snippet.WriteToClipboard(text) -> #(shell, WriteToClipboard(text))
      }
    }
    ExternalHandlerCompleted(result) -> {
      let #(run, action) = handle_external(shell, result)
      let shell = Shell(..shell, run:)

      case run.return {
        Ok(#(value, scope)) -> {
          let record =
            Executed(value, run.effects, readonly.new(shell.source.editable))
          let previous = [record, ..shell.previous]
          Shell(..shell, previous:, scope:)
          |> set_code(e.from_annotated(ir.vacant()))
        }
        _ -> #(shell, action)
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

  let source = snippet_analyse(source, scope, cache, shell.effect_types)
  #(Shell(..shell, source:, run:), FocusOnCode)
}

fn confirm(shell) {
  let Shell(effect_handlers: extrinsic, run:, ..) = shell
  let Run(started:, return:, effects:) = run
  case started, return {
    False, Ok(#(value, scope)) -> {
      finalize(shell, value, scope, effects)
    }
    False, Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
      case list.key_find(extrinsic, label) {
        Ok(blocking) -> {
          let #(return, action) = case blocking(lift) {
            Ok(thunk) -> #(return, RunExternalHandler(0, thunk))
            Error(reason) -> #(Error(#(reason, meta, env, k)), Nothing)
          }
          let run = Run(..run, started: True, return:)
          let shell = Shell(..shell, run:)

          #(shell, action)
        }
        _ -> #(shell, Nothing)
      }
    }
    _, _ -> #(Shell(..shell, run: Run(True, return, effects)), Nothing)
  }
}

fn finalize(shell, value, scope, effects) {
  let Shell(source:, previous:, ..) = shell
  let record = Executed(value, effects, readonly.new(source.editable))
  let previous = [record, ..previous]
  Shell(..shell, previous:, scope:)
  |> set_code(e.from_annotated(ir.vacant()))
}

// analyse stuff

// this is not just configurable for the reload case
fn snippet_analyse(snippet, scope, cache, effect_types) {
  let snippet.Snippet(editable:, ..) = snippet

  let refs = cache.type_map(cache)

  let analysis =
    analysis.do_analyse(
      editable,
      analysis.within_environment(scope, refs, Nil)
        |> analysis.with_effects(effect_types),
    )
  snippet.Snippet(..snippet, analysis: Some(analysis))
}

// runner stuff

fn new_run(editable, scope, cache) {
  Run(False, evaluate(editable, scope, cache), [])
}

fn run_update_cache(run, cache, effects) {
  let Run(started:, return:, ..) = run
  case return {
    Error(#(break.UndefinedReference(_), meta, env, k))
    | Error(#(break.UndefinedRelease(_, _, _), meta, env, k)) -> {
      let return = cache.run(return, cache, block.resume)
      case started {
        True -> {
          let #(return, action) = case lookup_external(return, effects) {
            Ok(#(lift, blocking)) -> {
              io.debug("real id needed")
              case blocking(lift) {
                Ok(thunk) -> #(return, RunExternalHandler(0, thunk))
                Error(reason) -> #(Error(#(reason, meta, env, k)), Nothing)
              }
            }
            Error(Nil) -> #(return, Nothing)
          }
          #(Run(..run, return:), action)
        }
        False -> #(run, Nothing)
      }
    }
    _ -> #(run, Nothing)
  }
}

fn handle_external(shell, result) {
  let Shell(run:, cache:, ..) = shell
  // TODO need to pair up with a run number
  let Run(return:, effects:, ..) = run
  case return {
    Error(#(break.UnhandledEffect(label, lift), meta, env, k)) -> {
      case result {
        Ok(reply) -> {
          let effects = [#(label, #(lift, reply)), ..effects]
          let return =
            cache.run(block.resume(reply, env, k), cache, block.resume)
          case lookup_external(return, shell.effect_handlers) {
            Ok(#(lift, blocking)) -> {
              case blocking(lift) {
                Ok(thunk) -> #(
                  Run(True, return, effects),
                  RunExternalHandler(0, thunk),
                )
                Error(reason) -> #(
                  Run(False, Error(#(reason, meta, env, k)), effects),
                  Nothing,
                )
              }
            }
            Error(Nil) -> #(Run(True, return, effects), Nothing)
          }
        }
        Error(reason) -> #(
          Run(False, Error(#(reason, meta, env, k)), effects),
          Nothing,
        )
      }
    }
    _ -> #(run, Nothing)
  }
}

fn lookup_external(return, extrinsic) {
  case return {
    Error(#(break.UnhandledEffect(label, lift), _meta, _env, _k)) -> {
      case list.key_find(extrinsic, label) {
        Ok(blocking) -> Ok(#(lift, blocking))
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

pub fn run_effect(lift, blocking) {
  case blocking(lift) {
    Ok(p) -> promise.map(p, fn(v) { ExternalHandlerCompleted(Ok(v)) })
    Error(reason) -> promise.resolve(ExternalHandlerCompleted(Error(reason)))
  }
}

pub fn write_to_clipboard(text) {
  promise.map(clipboard.write_text(text), fn(r) {
    CurrentMessage(snippet.ClipboardWriteCompleted(r))
  })
}

pub fn read_from_clipboard() {
  promise.map(clipboard.read_text(), fn(r) {
    CurrentMessage(snippet.ClipboardReadCompleted(r))
  })
}

pub type Status {
  Finished
  WillRunEffect(label: String)
  RunningEffect(label: String)
  RequireRelease(package: String, release: Int, cid: String)
  RequireReference(cid: String)
  AwaitingRelease(package: String, release: Int, cid: String)
  AwaitingReference(cid: String)
  Failed
}

// Needs to join against effects and sync client
// This double error handling from evaluated to 
pub fn status(shell) {
  let Shell(run:, effect_handlers:, ..) = shell
  case run.started, run.return {
    _, Ok(_) -> Finished
    False, Error(#(break.UnhandledEffect(label, _), _, _, _)) ->
      case list.key_find(effect_handlers, label) {
        Ok(_) -> WillRunEffect(label)
        Error(Nil) -> Failed
      }
    True, Error(#(break.UnhandledEffect(label, _), _, _, _)) ->
      RunningEffect(label)
    False, Error(#(break.UndefinedRelease(p, r, c), _, _, _)) ->
      RequireRelease(p, r, c)
    False, Error(#(break.UndefinedReference(c), _, _, _)) -> RequireReference(c)
    True, Error(#(break.UndefinedRelease(p, r, c), _, _, _)) ->
      AwaitingRelease(p, r, c)
    True, Error(#(break.UndefinedReference(c), _, _, _)) -> AwaitingReference(c)
    _, _ -> Failed
  }
}

pub fn evaluate(editable, scope, cache) {
  e.to_annotated(editable, [])
  |> ir.clear_annotation
  |> block.execute(scope)
  |> cache.run(cache, block.resume)
}
