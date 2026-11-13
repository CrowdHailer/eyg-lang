//// Transcripts as text for people and for judges.

import gleam/bit_array
import gleam/http
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import overlay/eval/transcript.{type Transcript}

/// Values and outputs longer than this are cut short.
pub const limit = 2000

/// A transcript in markdown, every turn, program and result, then the
/// effects and the workspace.
pub fn transcript(record: Transcript) -> String {
  let turns =
    list.index_map(record.turns, fn(turn, index) {
      let steps =
        list.map(turn.steps, fn(step) {
          let runs =
            list.map(step.runs, fn(run) {
              let output = case run.output {
                [] -> ""
                output ->
                  "\nPrinted:\n```\n" <> cut(string.concat(output)) <> "\n```"
              }
              "Ran:\n```eyg\n"
              <> run.code
              <> "\n```\nResult: "
              <> label(run.outcome)
              <> "\n```\n"
              <> cut(transcript.describe(run.outcome))
              <> "\n```"
              <> output
            })
          [thinking(step.thinking), string.trim(step.text), ..runs]
          |> list.filter(fn(part) { part != "" })
          |> list.map(fn(part) { "Agent: " <> part })
          |> string.join("\n\n")
        })
      "## Turn "
      <> int.to_string(index + 1)
      <> "\n\nUser: "
      <> turn.prompt
      <> "\n\n"
      <> string.join(steps, "\n\n")
    })
  let effects = case record.effects {
    [] -> []
    effects -> [
      "## Effects\n\n"
      <> string.join(
        list.map(effects, fn(effect) { "- " <> effect_line(effect) }),
        "\n",
      ),
    ]
  }
  let workspace = case record.workspace {
    None -> []
    Some([]) -> ["## Workspace\n\nThe workspace is empty."]
    Some(files) -> [
      "## Workspace\n\n"
      <> string.join(
        list.map(files, fn(file) {
          let #(path, contents) = file
          case bit_array.to_string(contents) {
            Ok(text) -> "### " <> path <> "\n\n```\n" <> cut(text) <> "\n```"
            Error(Nil) ->
              "### "
              <> path
              <> "\n\n"
              <> int.to_string(bit_array.byte_size(contents))
              <> " bytes of binary"
          }
        }),
        "\n\n",
      ),
    ]
  }
  list.flatten([turns, effects, workspace, [stop(record.stop)]])
  |> string.join("\n\n")
}

fn thinking(text) {
  case string.trim(text) {
    "" -> ""
    text -> "(thinking) " <> cut(text)
  }
}

fn label(outcome) {
  case outcome {
    transcript.Computed(..) -> "computed"
    transcript.TypeErrors(..) -> "type errors"
    transcript.InvalidCode(..) -> "invalid code"
    transcript.Exception(..) -> "exception"
    transcript.Aborted(..) -> "aborted"
    transcript.Unfinished(..) -> "unfinished"
  }
}

pub fn effect_line(effect: transcript.Effect) -> String {
  case effect {
    transcript.Fetch(by:, method:, url:, status:) -> {
      let by = case by {
        transcript.Program -> ""
        transcript.ModuleCache -> " (loading modules)"
      }
      let status = case status {
        Ok(status) -> int.to_string(status)
        Error(reason) -> "failed: " <> reason
      }
      http.method_to_string(method) <> " " <> url <> " " <> status <> by
    }
    transcript.Alert(message:) -> "alert: " <> message
    transcript.Prompt(question:) -> "prompt: " <> question
    transcript.Visit(url:) -> "visit: " <> url
    transcript.Download(name:) -> "download: " <> name
    transcript.Copy(text:) -> "copy: " <> cut(text)
    transcript.Service(name:) -> "service: " <> name
  }
}

pub fn stop(stop: transcript.Stop) -> String {
  case stop {
    transcript.Finished -> "The agent finished."
    transcript.ModelCallLimit(limit:) ->
      "Stopped after " <> int.to_string(limit) <> " model calls."
    transcript.ContextFailed(reason:) ->
      "The context failed to load: " <> reason
    transcript.ModelFailed(reason:) -> "The model failed: " <> reason
    transcript.Stuck -> "The session stopped before the agent finished."
  }
}

fn cut(text) {
  case string.length(text) > limit {
    True -> string.slice(text, 0, limit) <> "… (cut)"
    False -> text
  }
}
