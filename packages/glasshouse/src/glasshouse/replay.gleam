//// Replay a program against its journal.
////
//// Each effect the program performs is matched with the next recorded entry.
//// A match resumes the program with the recorded reply, nothing is performed.
//// Any difference is a divergence, the program did not behave as recorded.

import eyg/interpreter/state
import glasshouse/journal.{type Entry}
import glasshouse/secret.{type Secret}
import glasshouse/store.{type Store}
import glasshouse/value.{type Encoded}
import gleam/int

pub opaque type Replay {
  Replay(
    position: Int,
    remaining: List(Entry),
    store: Store,
    secrets: List(Secret),
  )
}

pub type Divergence {
  /// The program performed an effect after every recorded effect was used.
  Unrecorded(position: Int, label: String, lift: Encoded)
  /// The program performed a different effect to the one recorded.
  Mismatch(position: Int, expected: Entry, label: String, lift: Encoded)
  /// The program finished before every recorded effect was performed.
  Unperformed(position: Int, next: Entry)
  /// A recorded reply could not be decoded, the store is incomplete.
  Unreadable(position: Int, reason: String)
}

/// Start replaying a journal.
/// Secrets are the values to use for mounted secrets, the recording never holds them.
pub fn start(
  journal: List(Entry),
  store: Store,
  secrets: List(Secret),
) -> Replay {
  Replay(position: 0, remaining: journal, store:, secrets:)
}

/// Answer the next effect from the journal.
pub fn next(
  replay: Replay,
  label: String,
  lift: state.Value(m),
  meta: m,
) -> Result(#(state.Value(m), Entry, Replay), Divergence) {
  let Replay(position:, remaining:, store:, secrets:) = replay
  let lift = secret.redact(lift, secrets)
  case remaining {
    [] -> Error(Unrecorded(position, label, value.encode(lift)))
    [entry, ..rest] ->
      case entry.label == label && value.matches(lift, entry.lift, store) {
        False -> Error(Mismatch(position, entry, label, value.encode(lift)))
        True ->
          case value.decode(entry.reply, store, meta) {
            Ok(reply) -> {
              let reply = secret.restore(reply, secrets)
              let replay =
                Replay(..replay, position: position + 1, remaining: rest)
              Ok(#(reply, entry, replay))
            }
            Error(reason) -> Error(Unreadable(position, reason))
          }
      }
  }
}

/// Check every recorded effect was performed.
pub fn finish(replay: Replay) -> Result(Nil, Divergence) {
  case replay.remaining {
    [] -> Ok(Nil)
    [next, ..] -> Error(Unperformed(replay.position, next))
  }
}

/// The number of effects replayed so far.
pub fn position(replay: Replay) -> Int {
  replay.position
}

pub fn describe(divergence: Divergence, store: Store) -> String {
  case divergence {
    Unrecorded(position:, label:, lift:) ->
      "effect "
      <> int.to_string(position + 1)
      <> " was not recorded: "
      <> label
      <> "("
      <> value.render(lift, store)
      <> ")"
    Mismatch(position:, expected:, label:, lift:) ->
      "effect "
      <> int.to_string(position + 1)
      <> " differs, recorded "
      <> expected.label
      <> "("
      <> value.render(expected.lift, store)
      <> ") but the program performed "
      <> label
      <> "("
      <> value.render(lift, store)
      <> ")"
    Unperformed(position:, next:) ->
      "the program finished after "
      <> int.to_string(position)
      <> " effects, the recording continues with "
      <> next.label
      <> "("
      <> value.render(next.lift, store)
      <> ")"
    Unreadable(position:, reason:) ->
      "the reply to effect "
      <> int.to_string(position + 1)
      <> " could not be read: "
      <> reason
  }
}
