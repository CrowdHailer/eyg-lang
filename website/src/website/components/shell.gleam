import eyg/interpreter/block
import eyg/interpreter/state as istate
import eyg/ir/tree as ir
import gleam/javascript/promise
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import morph/analysis
import morph/editable as e
import plinth/browser/clipboard
import website/components/readonly
import website/components/runner
import website/components/snippet
import website/sync/cache

pub type ShellEntry {
  Executed(
    value: Option(istate.Value(Nil)),
    // The list of effects are kept in reverse order
    effects: List(runner.Effect(Nil)),
    source: readonly.Readonly,
  )
}

pub type ShellFailure {
  SnippetFailure(snippet.Failure)
  NoMoreHistory
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
    context: analysis.Context,
    // I need to rebuild because scope is difference and I want expression in example
    scope: runner.Scope(Nil),
    runner: runner.Block(Nil),
  )
}

// could just be given a snippet
pub fn init(effects, cache) {
  let source = e.from_annotated(ir.vacant())
  let scope = []
  let #(effect_types, effect_handlers) = listx.key_unzip(effects)
  let snippet = snippet.active(source)

  let context =
    analysis.context()
    |> analysis.with_effects(effect_types)
    |> update_context(cache)

  let source = snippet.editable |> e.to_annotated([]) |> ir.clear_annotation

  let runner =
    runner.init(block.execute(source, []), cache, effect_handlers, block.resume)
  Shell(
    failure: None,
    previous: [],
    source: snippet,
    cache: cache,
    context:,
    scope: scope,
    runner:,
  )
  |> snippet_analyse
}

fn update_context(context, cache) {
  analysis.Context(
    ..context,
    references: cache.type_map(cache),
    index: cache.package_index(cache),
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
  RunnerMessage(runner.BlockMessage(Nil))
  UserClickedPrevious(Int)
  PreviousMessage(Int, readonly.Message)
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
      let Shell(context:, runner:, ..) = shell
      let #(runner, action) = runner.update(runner, runner.UpdateCache(cache))
      let context = update_context(context, cache)
      let shell = Shell(..shell, context:, runner:)
      case action {
        runner.Nothing -> #(shell, Nothing)
        runner.RunExternalHandler(ref, thunk) -> #(
          shell,
          RunExternalHandler(ref, thunk),
        )
        runner.Conclude(return) -> finalize(shell, return)
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
    RunnerMessage(message) -> {
      let Shell(runner:, ..) = shell
      let #(runner, action) = runner.update(runner, message)
      let shell = Shell(..shell, runner:)
      case action {
        runner.Nothing -> #(shell, Nothing)
        runner.RunExternalHandler(id, thunk) -> #(
          shell,
          RunExternalHandler(id, thunk),
        )
        runner.Conclude(return) -> finalize(shell, return)
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
    PreviousMessage(index, message) -> {
      let assert Ok(#(pre, executed, post)) =
        listx.split_around(shell.previous, index)
      let pre = close_many_previous(pre)
      let post = close_many_previous(post)
      let Executed(a, b, r) = executed
      let #(r, action) = readonly.update(r, message)
      let previous = listx.gather_around(pre, Executed(a, b, r), post)
      let effect = case action {
        readonly.Nothing -> Nothing
        readonly.Fail(_message) -> Nothing
        readonly.MoveAbove -> Nothing
        readonly.MoveBelow -> Nothing
        readonly.WriteToClipboard(text) -> WriteToClipboard(text)
      }
      let shell = Shell(..shell, previous: previous)
      #(shell, effect)
    }
  }
}

fn set_code(shell, code) {
  let shell = Shell(..shell, source: snippet.active(code))
  new_code(shell)
}

// The snippet will have cleared it's analysis
fn new_code(shell) {
  let Shell(source:, scope:, runner:, ..) = shell
  let source = source.editable |> e.to_annotated([]) |> ir.clear_annotation

  let #(runner, action) =
    runner.update(runner, runner.Reset(block.execute(source, scope)))

  #(Shell(..shell, runner:) |> snippet_analyse, FocusOnCode)
}

fn confirm(shell) {
  let Shell(runner:, ..) = shell
  let #(runner, action) = runner.update(runner, runner.Start)
  let shell = Shell(..shell, runner:)
  case action {
    runner.Nothing -> #(shell, Nothing)
    runner.RunExternalHandler(id, thunk) -> #(
      shell,
      RunExternalHandler(id, thunk),
    )
    runner.Conclude(return) -> finalize(shell, return)
  }
}

fn finalize(shell, return) {
  let Shell(context:, source:, previous:, runner:, ..) = shell
  let #(value, scope) = return
  let record = Executed(value, runner.occured, readonly.new(source.editable))
  let previous = [record, ..previous]
  let #(bindings, tenv) = analysis.env_to_tenv(scope, Nil)
  let context = analysis.Context(..context, bindings:, scope: tenv)
  Shell(..shell, context:, previous:, scope:)
  |> set_code(e.from_annotated(ir.vacant()))
}

// analyse stuff

// this is not just configurable for the reload case
fn snippet_analyse(state) {
  let Shell(context:, source:, ..) = state
  let snippet.Snippet(editable:, ..) = source

  let analysis = analysis.do_analyse(editable, context)
  let source = snippet.Snippet(..source, analysis: Some(analysis))
  Shell(..state, source:)
}

// -----

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

pub fn evaluate(editable, scope, cache) {
  e.to_annotated(editable, [])
  |> ir.clear_annotation
  |> block.execute(scope)
  |> cache.run(cache, block.resume)
}
