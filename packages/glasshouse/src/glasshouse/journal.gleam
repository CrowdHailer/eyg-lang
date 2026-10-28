//// A journal records every effect a program performed, in the order they were performed.
////
//// Each entry has the request as the program made it and the reply the program received.
//// Replaying the program with the replies from its journal reproduces the run exactly,
//// EYG programs have no other way to observe the outside world.

import eyg/ir/dag_json as ir_json
import glasshouse/value.{type Encoded}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None}

pub type Entry {
  Entry(
    label: String,
    lift: Encoded,
    reply: Encoded,
    answer: Answer,
    /// The absolute path of a filesystem effect, programs can use relative paths.
    path: Option(String),
    /// Unix milliseconds, metadata only, never compared on replay.
    started: Int,
    duration: Int,
  )
}

/// How the effect was answered.
pub type Answer {
  /// The host performed the request.
  Performed
  /// A policy gate passed the request and the host performed it.
  Gated
  /// A policy gate changed the request before the host performed it.
  /// Only the CID of the request sent is kept, gates are where secrets are added.
  Altered(sent: String)
  /// A policy gate answered and nothing was performed.
  Mocked
  /// A reply recorded in an earlier run was reused, during evaluations.
  Cached
  /// The evaluation environment answered without touching the host.
  Simulated
}

pub fn answer_to_string(answer: Answer) -> String {
  case answer {
    Performed -> "performed"
    Gated -> "gated"
    Altered(_) -> "altered"
    Mocked -> "mocked"
    Cached -> "cached"
    Simulated -> "simulated"
  }
}

pub fn encode(entry: Entry) -> json.Json {
  let Entry(label:, lift:, reply:, answer:, path:, started:, duration:) = entry
  json.object([
    #("label", json.string(label)),
    #("lift", ir_json.to_data_model(lift)),
    #("reply", ir_json.to_data_model(reply)),
    #("answer", answer_encode(answer)),
    #("path", json.nullable(path, json.string)),
    #("started", json.int(started)),
    #("duration", json.int(duration)),
  ])
}

fn answer_encode(answer) {
  case answer {
    Altered(sent:) -> json.object([#("altered", json.string(sent))])
    _ -> json.string(answer_to_string(answer))
  }
}

pub fn decoder() -> decode.Decoder(Entry) {
  use label <- decode.field("label", decode.string)
  use lift <- decode.field("lift", ir_json.decoder(Nil))
  use reply <- decode.field("reply", ir_json.decoder(Nil))
  use answer <- decode.field("answer", answer_decoder())
  use path <- decode.optional_field(
    "path",
    None,
    decode.optional(decode.string),
  )
  use started <- decode.optional_field("started", 0, decode.int)
  use duration <- decode.optional_field("duration", 0, decode.int)
  decode.success(Entry(
    label:,
    lift:,
    reply:,
    answer:,
    path:,
    started:,
    duration:,
  ))
}

fn answer_decoder() {
  decode.one_of(
    {
      use name <- decode.then(decode.string)
      case name {
        "performed" -> decode.success(Performed)
        "gated" -> decode.success(Gated)
        "mocked" -> decode.success(Mocked)
        "cached" -> decode.success(Cached)
        "simulated" -> decode.success(Simulated)
        _ -> decode.failure(Performed, "answer")
      }
    },
    [
      decode.field("altered", decode.string, fn(sent) {
        decode.success(Altered(sent))
      }),
    ],
  )
}

/// CIDs of all stored modules the journal refers to.
pub fn references(journal: List(Entry)) -> List(String) {
  list.flat_map(journal, fn(entry) {
    list.append(value.references(entry.lift), value.references(entry.reply))
  })
  |> list.unique
}

/// Effects that changed something outside the program, by label.
pub fn is_write(label: String) -> Bool {
  case label {
    "WriteFile"
    | "AppendFile"
    | "DeleteFile"
    | "MakeDirectory"
    | "Clone"
    | "Commit" -> True
    _ -> False
  }
}
