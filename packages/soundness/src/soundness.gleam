//// Search for programs that the analysis accepts and eval rejects.

import gleam/int
import gleam/list
import soundness/generate
import soundness/generate_typed
import soundness/print
import soundness/property
import soundness/random

pub type Summary {
  Summary(
    checked: Int,
    rejected: Int,
    exhausted: Int,
    sound: Int,
    counterexamples: List(String),
    /// Why the analysis rejected programs, kept to spot a generator that is
    /// building nonsense rather than a type system that is being strict.
    rejections: List(String),
  )
}

pub fn empty() {
  Summary(0, 0, 0, 0, [], [])
}

/// Programs built from the type rules, see `soundness/generate_typed`.
pub fn search_typed(
  from from: Int,
  count count: Int,
  size size: Int,
  fuel fuel: Int,
  config config: generate_typed.Config,
) {
  fold(from, count, fn(summary, s) {
    let #(source, _type, _seed) =
      generate_typed.program(random.seed(s), config, size)
    record(summary, s, source, property.check(source, fuel))
  })
}

/// Programs built at random, see `soundness/generate`.
pub fn search(
  from from: Int,
  count count: Int,
  size size: Int,
  fuel fuel: Int,
) {
  fold(from, count, fn(summary, s) {
    let #(source, _seed) = generate.program(random.seed(s), size)
    record(summary, s, source, property.check(source, fuel))
  })
}

fn fold(from, count, run) {
  int.range(from: from, to: from + count, with: empty(), run: run)
}

fn record(summary: Summary, s, source, outcome) {
  let summary = Summary(..summary, checked: summary.checked + 1)
  case outcome {
    property.Rejected(reason) ->
      Summary(..summary, rejected: summary.rejected + 1, rejections: [
        reason <> " in " <> print.source(source),
        ..summary.rejections
      ])
    property.Exhausted -> Summary(..summary, exhausted: summary.exhausted + 1)
    property.Sound -> Summary(..summary, sound: summary.sound + 1)
    _ ->
      Summary(..summary, counterexamples: [
        "seed " <> int.to_string(s) <> " " <> property.report(source, outcome),
        ..summary.counterexamples
      ])
  }
}

pub fn render(summary: Summary) {
  let Summary(checked:, rejected:, exhausted:, sound:, counterexamples:, ..) =
    summary
  [
    "checked " <> int.to_string(checked),
    "rejected " <> int.to_string(rejected),
    "exhausted " <> int.to_string(exhausted),
    "sound " <> int.to_string(sound),
    "counterexamples " <> int.to_string(list.length(counterexamples)),
  ]
  |> list.append(list.reverse(counterexamples))
  |> string_join
}

fn string_join(lines) {
  case lines {
    [] -> ""
    [line] -> line
    [line, ..rest] -> line <> "\n" <> string_join(rest)
  }
}
