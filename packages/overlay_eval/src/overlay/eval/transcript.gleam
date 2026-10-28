//// The record of a session under eval.
////
//// A transcript keeps what the agent said, every program it ran with the
//// value it computed, every effect that reached the environment and the
//// workspace it left behind. Graders read transcripts, they never rerun a
//// session.

import eyg/analysis/type_/binding/debug as analysis_debug
import eyg/interpreter/simple_debug
import eyg/interpreter/state as istate
import eyg/parser
import gleam/dict
import gleam/http
import gleam/list
import gleam/option.{type Option}
import gleam/string
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool
import overlay/web/tools

pub type Transcript {
  Transcript(
    turns: List(Turn),
    effects: List(Effect),
    workspace: Option(List(#(String, BitArray))),
    model_calls: Int,
    stop: Stop,
  )
}

pub type Turn {
  Turn(prompt: String, steps: List(Step))
}

/// One reply from the model, with the programs it ran.
pub type Step {
  Step(thinking: String, text: String, runs: List(Run))
}

pub type Run {
  Run(code: String, outcome: Outcome, output: List(String))
}

pub type Value =
  istate.Value(tools.Meta)

pub type Outcome {
  Computed(value: Value)
  TypeErrors(reasons: List(String))
  InvalidCode(reason: String)
  Exception(reason: String)
  Aborted(reason: String)
  // The call never finished, it was stopped or could not start.
  Unfinished(reason: String)
}

/// An effect that reached the environment.
pub type Effect {
  Fetch(
    by: Requester,
    method: http.Method,
    url: String,
    status: Result(Int, String),
  )
  Alert(message: String)
  Prompt(question: String)
  Visit(url: String)
  Download(name: String)
  Copy(text: String)
  Service(name: String)
}

/// Programs the agent runs fetch, and so does Overlay to load modules and packages.
pub type Requester {
  Program
  ModuleCache
}

pub type Stop {
  // The agent finished every turn.
  Finished
  ModelCallLimit(limit: Int)
  // The context of the session could not be loaded.
  ContextFailed(reason: String)
  // A request to the model failed.
  ModelFailed(reason: String)
  // The session stopped with nothing left to do before the agent finished.
  Stuck
}

/// Build turns from a session's history and finished runs, both most recent
/// first as Overlay keeps them.
pub fn turns(
  history: List(chat.Message(tool.Call)),
  runs: List(tools.Progress),
) -> List(Turn) {
  let #(turns, _runs) =
    list.fold(
      list.reverse(history),
      #([], list.reverse(runs)),
      fn(acc, message) {
        let #(turns, runs) = acc
        case message, turns {
          chat.UserMessage(text:, ..), _ -> #([Turn(text, []), ..turns], runs)
          chat.AssistantMessage(thinking:, text:, tool_calls:), [turn, ..rest]
          -> {
            let #(step_runs, runs) = take_runs(tool_calls, runs)
            let step = Step(thinking:, text:, runs: step_runs)
            #(
              [Turn(..turn, steps: list.append(turn.steps, [step])), ..rest],
              runs,
            )
          }
          _, _ -> acc
        }
      },
    )
  list.reverse(turns)
}

/// Runs are finished in the order the calls were made, calls without a run
/// had not finished.
fn take_runs(calls: List(tool.Call), runs: List(tools.Progress)) {
  list.map_fold(calls, runs, fn(runs, call) {
    let code = code(call)
    case runs {
      [progress, ..rest] -> #(
        rest,
        Run(
          code:,
          outcome: outcome(progress.call),
          output: list.reverse(progress.output),
        ),
      )
      [] -> #([], Run(code:, outcome: Unfinished("not finished"), output: []))
    }
  })
  |> fn(result) {
    // Only run calls are programs, other tool calls such as an unknown tool
    // also have retained outcomes. Consume those outcomes in order.
    let programs =
      list.zip(calls, result.1)
      |> list.filter_map(fn(pair) {
        case pair.0.function.name {
          "run" -> Ok(pair.1)
          _ -> Error(Nil)
        }
      })
    #(programs, result.0)
  }
}

fn code(call: tool.Call) {
  case dict.get(call.function.arguments, "code") {
    Ok(utils.String(code)) -> code
    _ -> ""
  }
}

pub fn outcome(call: tools.Call) -> Outcome {
  case call {
    tools.Successful(value) -> Computed(value)
    tools.Errored(errors) ->
      TypeErrors(list.map(errors, fn(error) { analysis_debug.reason(error.1) }))
    tools.InvalidCode(reason, code) ->
      InvalidCode(parser.format_error(reason, code))
    tools.Exception(reason) -> Exception(simple_debug.describe(reason))
    tools.Aborted(reason) -> Aborted(reason)
    tools.UnknownTool(name:) -> Unfinished("unknown tool " <> name)
    tools.BadArguments(reasons) ->
      Unfinished("bad arguments " <> string.inspect(reasons))
    tools.Handling(..) | tools.Pulling(..) | tools.Fetching(..) ->
      Unfinished("still running")
  }
}

/// Every run in the order it was made.
pub fn runs(transcript: Transcript) -> List(Run) {
  list.flat_map(transcript.turns, fn(turn) {
    list.flat_map(turn.steps, fn(step) { step.runs })
  })
}

/// The agent's final words in a turn.
pub fn reply(turn: Turn) -> String {
  case list.last(turn.steps) {
    Ok(step) -> step.text
    Error(Nil) -> ""
  }
}

/// A short description of an outcome, as the agent was told it.
pub fn describe(outcome: Outcome) -> String {
  case outcome {
    Computed(value) -> simple_debug.inspect(value)
    TypeErrors(reasons) -> string.join(reasons, "\n")
    InvalidCode(reason) -> reason
    Exception(reason) -> reason
    Aborted(reason) -> reason
    Unfinished(reason) -> reason
  }
}
