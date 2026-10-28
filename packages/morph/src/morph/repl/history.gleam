import eyg/interpreter/state
import gleam/option.{type Option}
import morph/buffer

pub type Entry(meta) {
  Entry(
    outcome: Outcome(meta),
    effects: List(EffectRecord(meta)),
    buffer: buffer.Buffer,
  )
}

pub type Outcome(meta) {
  Success(Option(state.Value(meta)))
  Aborted(String)
  Exception(state.Debug(meta))
}

pub type EffectRecord(meta) =
  #(String, #(state.Value(meta), state.Value(meta)))
