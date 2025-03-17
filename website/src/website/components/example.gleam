import eyg/interpreter/expression
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/option.{Some}
import morph/editable as e
import website/components/runner.{type Runner}
import website/components/snippet.{type Snippet, Snippet}
import website/mount/interactive
import website/sync/cache

// throwing away the run state when a task might complete later is a problem
// This is an issue of named proceses an a pid id wouldn't have the same problem
// the pid id would be fine but how do we handle the multiple effects run in a single run
// Should the runner be built with a builder pattern potentially the runner can have a paramerisation of return type
// However all of this might be overkill if it can't be used by reload

// The interesting situation was when a run had started but was waiting on a ref because then there was no task function

// run.update(start) -> #(returniswatingref, Nothing)
// run.update(ExtrinsicHandlerReply) ->

// Cant be unstarted and waiting for a reply
// Can be started and not waiting for a reply

// Turn break around could have failure type but I'm interested in undefined variable returning something lazy
// vacant code cold also potentially have a test value
// pub type Reason(m, c) {
//   NotAFunction(v.Value(m, c))
//   UndefinedVariable(String)
//   UndefinedBuiltin(String)
//   UndefinedReference(String) + go
//   UndefinedRelease(package: String, release: Int, cid: String) + go
//   Vacant
//   NoMatch(term: v.Value(m, c))
//   UnhandledEffect(String, v.Value(m, c)) + taskref
//   IncorrectTerm(expected: String, got: v.Value(m, c))
//   MissingField(String)
// }

// We don't have a go step on builtins as we ALWAYS go but we need a variable saying will run for cache update
// It's sorta useful to say will run for further effects as we can step through effects potentially although you could handle that outse
// but if you did handle that outside would original go be handled outside probably

// next ref

// Might want auto continue to depend on effect, in which case this is just more composition of execute etc

// Might not want a global effect to run from an example for example wait 20 min and then alert is very confusing if using another example

// continue awaiting: extrinsic_ref,next_ref
// cancel sets awaiting to none and continue to false

// is reusing Return the problem here or more accuratly break

// is there a task id and ref id equivalence ones idempotent so probably not.

// unhandled effect is the return value 
// if you change the effects then there will be a task that is not expected

// run once doesn' work with bools if waiting on ref
// I don't like fixed named enums it leads to a lot of invalid type modelling
// reload does work on expression

// interactive.block(tree, scope)
// expression

pub type Example {
  Example(cache: cache.Cache, snippet: Snippet, runner: Runner(Nil))
}

pub fn from_block(bytes, cache, extrinsic) {
  let assert Ok(source) = dag_json.from_block(bytes)

  let snippet =
    e.from_annotated(source)
    |> e.open_all
    |> snippet.init()
  let runner = runner.init(execute_snippet(snippet), cache, extrinsic)

  Example(cache:, snippet:, runner:)
  |> do_analysis
}

pub fn finish_editing(state) {
  let Example(snippet:, runner:, ..) = state
  let snippet = snippet.finish_editing(snippet)
  let runner = runner.stop(runner)
  Example(..state, snippet:, runner:)
}

pub fn update_cache(state, cache) {
  let Example(runner:, ..) = state
  let #(runner, action) = runner.update(runner, runner.UpdateCache(cache))
  let state =
    Example(..state, runner:)
    |> do_analysis
  #(state, action)
}

pub type Message {
  SnippetMessage(snippet.Message)
  RunnerMessage(runner.Message(Nil))
}

pub type Action {
  Nothing
  Failed(snippet.Failure)
  ReturnToCode
  FocusOnInput
  ReadFromClipboard
  WriteToClipboard(text: String)
  RunExternalHander(id: Int, thunk: runner.Thunk(Nil))
}

pub fn update(state, message) {
  case message {
    SnippetMessage(message) -> {
      let Example(snippet:, ..) = state
      let #(snippet, action) = snippet.update(snippet, message)
      let state = Example(..state, snippet:)
      case action {
        snippet.Nothing -> #(state, Nothing)
        snippet.NewCode -> {
          let Example(runner:, ..) = state
          let return = execute_snippet(snippet)
          let #(runner, action) = runner.update(runner, runner.Reset(return))
          case action {
            runner.Nothing -> Nil
            _ ->
              panic as "reset expected to always return nothing action becase continue is set to false."
          }
          let state = Example(..state, runner:)
          let state = do_analysis(state)
          #(state, Nothing)
        }
        snippet.Confirm -> {
          let Example(runner:, ..) = state

          let #(runner, action) = runner.update(runner, runner.Start)
          let state = Example(..state, runner:)
          let action = case action {
            runner.Nothing -> Nothing
            runner.RunExternalHander(id, thunk) -> RunExternalHander(id, thunk)
          }
          #(state, action)
        }
        snippet.Failed(failure) -> #(state, Failed(failure))
        snippet.ReturnToCode -> #(state, ReturnToCode)
        snippet.FocusOnInput -> #(state, FocusOnInput)
        snippet.ToggleHelp -> #(state, Nothing)
        snippet.MoveAbove -> #(state, Nothing)
        snippet.MoveBelow -> #(state, Nothing)
        snippet.ReadFromClipboard -> #(state, ReadFromClipboard)
        snippet.WriteToClipboard(text) -> #(state, WriteToClipboard(text))
      }
    }
    RunnerMessage(message) -> {
      let Example(runner:, ..) = state
      let #(runner, action) = runner.update(runner, message)
      let state = Example(..state, runner:)
      let action = case action {
        runner.Nothing -> Nothing
        runner.RunExternalHander(id, thunk) -> RunExternalHander(id, thunk)
      }
      #(state, action)
    }
  }
}

fn execute_snippet(snippet) {
  let Snippet(editable:, ..) = snippet
  let source = editable |> e.to_annotated([]) |> ir.clear_annotation
  expression.execute(source, [])
}

fn do_analysis(state) {
  let Example(cache:, snippet:, ..) = state
  let scope = []
  // TODO effects should be from init
  let effects = []
  let analysis =
    interactive.do_analysis(snippet.editable, scope, cache, effects)
  let snippet = Snippet(..snippet, analysis: Some(analysis))
  Example(..state, snippet:)
}
