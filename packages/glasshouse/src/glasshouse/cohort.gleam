//// Compare sessions that ran the same task with different setups.
////
//// A cohort is a baseline session and variants run against its environment.
//// Each is summarised by what it cost, what it did and what it changed.

import glasshouse/diff
import glasshouse/run
import glasshouse/session.{type Session, type Usage, Usage}
import glasshouse/store.{type Store}
import glasshouse/timeline
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Summary {
  Summary(
    name: String,
    session: String,
    generations: Int,
    /// Generations answered from the recording, they cost no tokens.
    recorded: Int,
    /// Tokens the model was asked to process.
    live: Usage,
    /// Tokens the recording saved.
    saved: Usage,
    tool_calls: Int,
    effects: Int,
    /// Files changed, with lines added and removed.
    changes: List(Change),
    answer: String,
    /// Why the variant could not be reproduced to the end.
    stopped: Option(String),
  )
}

pub type Change {
  Change(path: String, added: Int, removed: Int)
}

pub fn summarize(name: String, session: Session, store: Store) -> Summary {
  let generations = session.generations(session)
  let #(live, saved) = session.usage(session)
  let recorded = list.count(generations, fn(g) { g.source == session.Recorded })
  let runs = session.runs(session)
  let answer =
    generations
    |> list.filter(fn(g) { g.content != "" })
    |> list.last
    |> fn(last) {
      case last {
        Ok(g) -> g.content
        Error(Nil) -> ""
      }
    }
  Summary(
    name:,
    session: session.id,
    generations: list.length(generations),
    recorded:,
    live:,
    saved:,
    tool_calls: list.length(list.flat_map(generations, fn(g) { g.tool_calls })),
    effects: list.fold(runs, 0, fn(total, run) {
      total + list.length(run.journal)
    }),
    changes: changes(session, store),
    answer:,
    stopped: stopped(session),
  )
}

/// The reason a run failed when it stopped at an effect the reproduction could not answer.
pub fn unreproducible(reason: String) -> String {
  "not reproducible: " <> reason
}

/// Why a variant could not be reproduced to the end, if it stopped.
pub fn stopped(session: Session) -> Option(String) {
  session.runs(session)
  |> list.find_map(fn(run) {
    case run.outcome {
      run.Failed(reason: "not reproducible: " <> reason) -> Ok(reason)
      _ -> Error(Nil)
    }
  })
  |> option.from_result
}

/// Every file the session changed, comparing its first and final known content.
pub fn changes(session: Session, store: Store) -> List(Change) {
  let frames = timeline.frames(session, store)
  let modified =
    list.fold(frames, dict.new(), fn(acc, frame) {
      case frame.change {
        Some(timeline.Wrote(path:, ..) as change)
        | Some(timeline.Removed(path:, ..) as change) ->
          case dict.has_key(acc, path) {
            True -> acc
            False -> dict.insert(acc, path, before(change))
          }
        Some(_) -> acc
        None -> acc
      }
    })
  let final = case list.last(frames) {
    Ok(frame) -> frame.files
    Error(Nil) -> dict.new()
  }
  dict.to_list(modified)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(entry) {
    let #(path, before) = entry
    let after = case dict.get(final, path) {
      Ok(timeline.File(content)) -> option.unwrap(timeline.text(content), "")
      _ -> ""
    }
    let #(added, removed) = diff.stats(diff.lines(before, after))
    Change(path:, added:, removed:)
  })
}

fn before(change) {
  case change {
    timeline.Wrote(before: Some(timeline.File(content)), ..)
    | timeline.Removed(before: Some(timeline.File(content)), ..) ->
      option.unwrap(timeline.text(content), "")
    _ -> ""
  }
}

pub fn encode(summary: Summary) -> json.Json {
  let Summary(
    name:,
    session:,
    generations:,
    recorded:,
    live:,
    saved:,
    tool_calls:,
    effects:,
    changes:,
    answer:,
    stopped:,
  ) = summary
  json.object([
    #("name", json.string(name)),
    #("session", json.string(session)),
    #("generations", json.int(generations)),
    #("recorded", json.int(recorded)),
    #("live", usage_encode(live)),
    #("saved", usage_encode(saved)),
    #("tool_calls", json.int(tool_calls)),
    #("effects", json.int(effects)),
    #(
      "changes",
      json.array(changes, fn(change) {
        json.object([
          #("path", json.string(change.path)),
          #("added", json.int(change.added)),
          #("removed", json.int(change.removed)),
        ])
      }),
    ),
    #("answer", json.string(answer)),
    #("stopped", json.nullable(stopped, json.string)),
  ])
}

fn usage_encode(usage: Usage) {
  json.object([
    #("input", json.int(usage.input)),
    #("output", json.int(usage.output)),
  ])
}

pub fn decoder() -> decode.Decoder(Summary) {
  let usage = {
    use input <- decode.field("input", decode.int)
    use output <- decode.field("output", decode.int)
    decode.success(Usage(input:, output:))
  }
  use name <- decode.field("name", decode.string)
  use session <- decode.field("session", decode.string)
  use generations <- decode.field("generations", decode.int)
  use recorded <- decode.field("recorded", decode.int)
  use live <- decode.field("live", usage)
  use saved <- decode.field("saved", usage)
  use tool_calls <- decode.field("tool_calls", decode.int)
  use effects <- decode.field("effects", decode.int)
  use changes <- decode.field(
    "changes",
    decode.list({
      use path <- decode.field("path", decode.string)
      use added <- decode.field("added", decode.int)
      use removed <- decode.field("removed", decode.int)
      decode.success(Change(path:, added:, removed:))
    }),
  )
  use answer <- decode.field("answer", decode.string)
  use stopped <- decode.field("stopped", decode.optional(decode.string))
  decode.success(Summary(
    name:,
    session:,
    generations:,
    recorded:,
    live:,
    saved:,
    tool_calls:,
    effects:,
    changes:,
    answer:,
    stopped:,
  ))
}

/// A report is the baseline's summary first, then each variant.
pub fn report_encode(baseline: String, summaries: List(Summary)) -> json.Json {
  json.object([
    #("baseline", json.string(baseline)),
    #("variants", json.array(summaries, encode)),
  ])
}

pub fn report_decoder() -> decode.Decoder(#(String, List(Summary))) {
  use baseline <- decode.field("baseline", decode.string)
  use variants <- decode.field("variants", decode.list(decoder()))
  decode.success(#(baseline, variants))
}

/// Total tokens for a usage.
pub fn tokens(usage: Usage) -> Int {
  usage.input + usage.output
}

/// A table comparing summaries, for the terminal, paths are shown relative to the directory.
pub fn table(summaries: List(Summary), directory: String) -> String {
  let header = [
    "variant",
    "generations",
    "replayed",
    "tokens",
    "saved",
    "tools",
    "effects",
    "files",
    "result",
  ]
  let rows =
    list.map(summaries, fn(s) {
      [
        s.name,
        int.to_string(s.generations),
        int.to_string(s.recorded),
        int.to_string(tokens(s.live)),
        int.to_string(tokens(s.saved)),
        int.to_string(s.tool_calls),
        int.to_string(s.effects),
        list.map(s.changes, fn(c) {
          timeline.relative(c.path, directory)
          <> " +"
          <> int.to_string(c.added)
          <> " -"
          <> int.to_string(c.removed)
        })
          |> string.join(", "),
        case s.stopped {
          Some(reason) -> "stopped: " <> reason
          None -> first_line(s.answer)
        },
      ]
    })
  let widths =
    list.fold([header, ..rows], list.map(header, fn(_) { 0 }), fn(widths, row) {
      list.map2(widths, row, fn(w, cell) { int.max(w, string.length(cell)) })
    })
  [header, ..rows]
  |> list.map(fn(row) {
    list.map2(row, widths, fn(cell, width) { string.pad_end(cell, width, " ") })
    |> string.join("  ")
    |> string.trim_end
  })
  |> string.join("\n")
}

fn first_line(text) {
  let line = case string.split_once(text, "\n") {
    Ok(#(line, _)) -> line
    Error(Nil) -> text
  }
  case string.length(line) > 48 {
    True -> string.slice(line, 0, 48) <> "…"
    False -> line
  }
}
