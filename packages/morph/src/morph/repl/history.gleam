import eyg/interpreter/state
import gleam/option.{type Option}
import morph/buffer

pub type Entry(meta) {
  Entry(
    value: Option(state.Value(meta)),
    effects: List(EffectRecord(meta)),
    buffer: buffer.Buffer,
  )
}

pub type EffectRecord(meta) =
  #(String, #(state.Value(meta), state.Value(meta)))
