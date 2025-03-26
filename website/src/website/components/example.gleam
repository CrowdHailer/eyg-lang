//// This example component is built on the snippet component and runner headless component
//// 
//// It is an effectful expression example context
////  - scope is empty
////  - blocks ending in vacant nodes are errors
//// 
//// It is stateful and sync to be useful in the component tree of a webpage.
//// All state information is available to a render function
//// 
//// It's also important that execution can be stopped. 
//// When a user switches to another example a delayed effect from the first example should not fire.
//// For example a program could be written to wait 5 minutes and then alert. 
//// If coding elsewhere that alert will be very confusing.
//// 
//// A previous experiment tried to have a `Run` component, instead of runner.
//// The difference would be that code could not be edited.
//// Doing this leave a problem of handling async replies from external handlers.
//// The next field in the runner needs to persist over code changes so that each async reply message gets a unique ref.
//// This could be handled outside the component but it makes sense to keep internally to simplify higher layers.
//// 
//// Having a continue flag and awaiting field seems like overkill. 
//// It is not elegant but is necessary to handle the case where a user has started the run
//// and the return state is a `MissingReference` or `MissingRelease`.
//// The task field must be None but state needs to be recorded that the user has started the run.
//// 
//// The `break.Reason` type is reused and it misses information like if a missing reference is in the process of being looked up
//// This type could be refactored to accomodate this extra data, or by grouping errors to recoverable and not.
//// 
//// I don't think this is a good idea because the `break.Reason` type should not depend on editor usage.
//// There are also other possible usecases like supercompilation where a `MissingVariable` could be recoverable.
//// 
//// ## Improvements
//// 
////  1. The runner could be parameterised by resume function so that it could run blocks or expressions.
////    This would make it reusable in the shell but that seems such a disparate environment is it worth it.
//// 
//// 2. The runner could be more flexible and a builder pattern used to specify effects resume etc.
//// 
//// 3. Replace continue boolean with an enum of `Zero` `Once` `More` so that effects could finish and wait for user input

import eyg/analysis/type_/binding
import eyg/interpreter/expression
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/listx
import gleam/option.{Some}
import morph/analysis
import morph/editable as e
import website/components/runner
import website/components/snippet.{type Snippet, Snippet}
import website/sync/cache

pub type Example {
  Example(
    cache: cache.Cache,
    snippet: Snippet,
    effects: List(#(String, #(binding.Mono, binding.Mono))),
    runner: runner.Expression(Nil),
  )
}

pub fn from_block(bytes, cache, extrinsic) {
  let assert Ok(source) = dag_json.from_block(bytes)
  init(source, cache, extrinsic)
}

pub fn init(source, cache, extrinsic) {
  let #(effects, handlers) = listx.key_unzip(extrinsic)

  let snippet =
    e.from_annotated(source)
    |> e.open_all
    |> snippet.init()
  let runner =
    runner.init(execute_snippet(snippet), cache, handlers, expression.resume)

  Example(cache:, snippet:, effects:, runner:)
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
    Example(..state, cache:, runner:)
    |> do_analysis
  #(state, action)
}

pub type Message {
  SnippetMessage(snippet.Message)
  RunnerMessage(runner.ExpressionMessage(Nil))
}

pub type Action {
  Nothing
  Failed(snippet.Failure)
  ReturnToCode
  FocusOnInput
  ToggleHelp
  ReadFromClipboard
  WriteToClipboard(text: String)
  RunExternalHandler(id: Int, thunk: runner.Thunk(Nil))
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
          #(state, ReturnToCode)
        }
        snippet.Confirm -> {
          let Example(runner:, ..) = state
          let #(runner, action) = runner.update(runner, runner.Start)
          let state = Example(..state, runner:)
          let action = case action {
            runner.Nothing -> Nothing
            runner.RunExternalHandler(id, thunk) ->
              RunExternalHandler(id, thunk)
            runner.Conclude(_) -> Nothing
          }
          #(state, action)
        }
        snippet.Failed(failure) -> #(state, Failed(failure))
        snippet.ReturnToCode -> #(state, ReturnToCode)
        snippet.FocusOnInput -> #(state, FocusOnInput)
        snippet.ToggleHelp -> #(state, ToggleHelp)
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
        runner.RunExternalHandler(id, thunk) -> RunExternalHandler(id, thunk)
        runner.Conclude(_) -> Nothing
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
  let Example(cache:, snippet:, effects:, ..) = state

  let analysis =
    analysis.do_analyse(
      snippet.editable,
      analysis.context()
        |> analysis.with_references(cache.type_map(cache))
        |> analysis.with_effects(effects)
        |> analysis.with_index(cache.package_index(cache)),
    )
  let snippet = Snippet(..snippet, analysis: Some(analysis))
  Example(..state, snippet:)
}
