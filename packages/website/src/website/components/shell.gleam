import eyg/interpreter/state as istate
import gleam/option.{type Option}
import website/components/readonly
import website/components/runner
import website/components/snippet

pub type ShellEntry {
  Executed(
    value: Option(istate.Value(List(Int))),
    // The list of effects are kept in reverse order
    effects: List(runner.Effect(Nil)),
    source: readonly.Readonly,
  )
}

pub type ShellFailure {
  SnippetFailure(snippet.Failure)
  NoMoreHistory
}
