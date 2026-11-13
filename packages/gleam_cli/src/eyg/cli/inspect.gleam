//// Show what happened in a trace, or the state at a single effect.
////
//// Without a step the timeline of the session is shown, each effect is numbered.
//// With a step the effect is shown with the files known after it and any change it made.

import eyg/cli/internal/config
import eyg/cli/internal/traces
import eyg/cli/replay
import glasshouse/archive
import glasshouse/diff
import glasshouse/journal
import glasshouse/session.{type Session}
import glasshouse/store.{type Store}
import glasshouse/timeline
import glasshouse/value
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import loam/system

pub fn execute(
  path: String,
  step: Option(Int),
  _config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use archive <- system.then(traces.load(path))
  use archive <- system.try(archive)
  let archive.Archive(session:, store:, ..) = archive
  let frames = timeline.frames(session, store)
  case step {
    None -> {
      use Nil <- system.map(
        system.stdout(timeline_text(session, frames, store)),
      )
      Ok(0)
    }
    Some(step) ->
      case list.drop(frames, step) {
        [frame, ..] -> {
          use Nil <- system.map(
            system.stdout(frame_text(session, frame, store)),
          )
          Ok(0)
        }
        [] ->
          system.Done(Error(
            "there is no step "
            <> int.to_string(step)
            <> ", the trace has "
            <> int.to_string(list.length(frames))
            <> " effects",
          ))
      }
  }
}

/// Every event in the session, with the effects of each run numbered.
pub fn timeline_text(
  session: Session,
  frames: List(timeline.Frame),
  store: Store,
) -> String {
  let header = [
    "session " <> session.id <> " in " <> session.cwd,
    ..case session.agent {
      Some(agent) -> ["agent " <> agent.provider <> " " <> agent.model]
      None -> []
    }
  ]
  let events =
    list.index_map(session.events, fn(event, i) {
      let number = string.pad_start(int.to_string(i + 1), 3, " ") <> " "
      case event {
        session.Execution(run:) -> {
          let effects =
            list.filter(frames, fn(frame) { frame.event == i })
            |> list.map(fn(frame) {
              "      " <> frame_line(frame, session.cwd, store)
            })
          [
            number
              <> replay.run_name(run, session.cwd)
              <> "  "
              <> plural(list.length(run.journal), "effect"),
            ..effects
          ]
        }
        session.Prompt(text:, ..) -> [number <> "prompt " <> quote(text)]
        session.Generated(generation:) -> [
          number
          <> "generation "
          <> int.to_string(generation.usage.input)
          <> " in, "
          <> int.to_string(generation.usage.output)
          <> " out tokens"
          <> case generation.tool_calls {
            [] -> ""
            calls -> ", " <> plural(list.length(calls), "tool call")
          }
          <> case generation.source {
            session.Live -> ""
            session.Recorded -> ", replayed"
          }
          <> case generation.error {
            Some(reason) -> ", failed: " <> reason
            None ->
              case generation.content {
                "" -> ""
                content -> " " <> quote(content)
              }
          },
        ]
        session.ToolResult(call_id:, text:, ..) -> [
          number <> "tool result " <> call_id <> " " <> quote(text),
        ]
      }
    })
    |> list.flatten
  string.join(list.append(header, events), "\n")
}

fn frame_line(frame: timeline.Frame, cwd, store) {
  let entry = frame.entry
  let index = string.pad_start(int.to_string(frame.index), 3, " ")
  let label = string.pad_end(entry.label, 14, " ")
  let subject = timeline.subject(entry, cwd, store)
  let change = case frame.change {
    Some(change) -> change_summary(change)
    None -> ""
  }
  index <> "  " <> label <> subject <> change
}

fn change_summary(change) {
  case timeline.change_diff(change) {
    Some(edits) -> {
      let #(added, removed) = diff.stats(edits)
      case timeline.is_modification(change) {
        True -> "  +" <> int.to_string(added) <> " -" <> int.to_string(removed)
        False -> ""
      }
    }
    None ->
      case change {
        timeline.Cloned(commit:, ..) -> "  at " <> string.slice(commit, 0, 12)
        timeline.Committed(commit:, ..) -> "  " <> string.slice(commit, 0, 12)
        timeline.Read(content:, ..) -> "  " <> content_size(content)
        _ -> ""
      }
  }
}

/// One effect, the change it made and the files known after it.
pub fn frame_text(
  session: Session,
  frame: timeline.Frame,
  store: Store,
) -> String {
  let entry = frame.entry
  let run =
    session.runs(session)
    |> list.find(fn(run) { run.id == frame.run })
  let run = case run {
    Ok(run) -> replay.run_name(run, session.cwd)
    Error(Nil) -> frame.run
  }
  let header =
    "effect "
    <> int.to_string(frame.index)
    <> " "
    <> entry.label
    <> " in "
    <> run
    <> " ("
    <> journal.answer_to_string(entry.answer)
    <> ")"
  let details =
    list.flatten([
      case entry.path {
        Some(path) -> ["path    " <> path]
        None -> []
      },
      ["request " <> value.summary(entry.lift, store, 400)],
      ["reply   " <> value.summary(entry.reply, store, 400)],
      case entry.answer {
        journal.Altered(sent:) -> [
          "sent    a request changed by the policy, " <> sent,
        ]
        _ -> []
      },
    ])
  let changes = case frame.change {
    Some(change) ->
      case timeline.change_diff(change) {
        Some(edits) ->
          case timeline.is_modification(change) {
            True -> ["", unified(edits)]
            False -> []
          }
        None -> []
      }
    None -> []
  }
  let files = [
    "",
    "files known after this effect",
    ..list.map(timeline.listing(frame.files), fn(entry) {
      let #(path, node) = entry
      let changed = case frame.change {
        Some(change) ->
          case
            timeline.change_path(change) == path
            && timeline.is_modification(change)
          {
            True -> " (changed)"
            False -> ""
          }
        _ -> ""
      }
      "  "
      <> string.pad_end(timeline.relative(path, session.cwd), 40, " ")
      <> " "
      <> node_summary(node)
      <> changed
    })
  ]
  string.join(list.flatten([[header], details, changes, files]), "\n")
}

fn unified(edits) {
  diff.hunks(edits, 3)
  |> list.map(fn(hunk) {
    list.map(hunk.edits, fn(edit) {
      case edit {
        diff.Keep(line) -> " " <> line
        diff.Insert(line) -> "+" <> line
        diff.Delete(line) -> "-" <> line
      }
    })
    |> string.join("\n")
  })
  |> string.join("\n...\n")
}

fn node_summary(node) {
  case node {
    timeline.File(content) -> content_size(content)
    timeline.Directory -> "directory"
    timeline.Checkout(url:, commit:) ->
      "clone of " <> url <> " at " <> string.slice(commit, 0, 12)
    timeline.Absent -> "deleted"
  }
}

fn content_size(content) {
  case content {
    timeline.Whole(bytes) -> bytes_text(bytes)
    timeline.Part(offset:, bytes:) ->
      bytes_text(bytes) <> " read from " <> int.to_string(offset)
    timeline.Ending(bytes) -> bytes_text(bytes) <> " appended"
    timeline.Unseen(Some(size)) -> int.to_string(size) <> " bytes, not read"
    timeline.Unseen(None) -> "not read"
  }
}

fn bytes_text(bytes) {
  int.to_string(bit_array.byte_size(bytes)) <> " bytes"
}

fn plural(count, word) {
  int.to_string(count)
  <> " "
  <> word
  <> case count {
    1 -> ""
    _ -> "s"
  }
}

fn quote(text) {
  let line =
    string.split(text, "\n")
    |> list.map(string.trim)
    |> list.filter(fn(line) { line != "" })
    |> string.join(" ")
  let line = case string.length(line) > 60 {
    True -> string.slice(line, 0, 60) <> "…"
    False -> line
  }
  "\"" <> line <> "\""
}
