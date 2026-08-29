import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/state
import gleam/list

/// The harness types concretly implementing the browser harness effect types
pub type Harness(eff, meta) =
  List(Interface(eff, meta))

pub type Interface(eff, meta) {
  Interface(
    name: String,
    lift_type: binding.Mono,
    lower_type: binding.Mono,
    decode: fn(state.Value(meta)) -> Result(eff, state.Reason(meta)),
  )
}

/// Narrow a harness to a subset of effects.
pub fn take(
  effects: Harness(eff, meta),
  labels: List(String),
) -> Harness(eff, meta) {
  list.filter(effects, fn(interface) {
    let Interface(name:, ..) = interface
    list.any(labels, fn(l) { l == name })
  })
}

/// Cast a rasied effect to an effect type in a harness
pub fn cast(
  effects: Harness(eff, a),
  label: String,
  input: state.Value(a),
) -> Result(eff, state.Reason(a)) {
  case list.find(effects, fn(i) { i.name == label }) {
    Ok(Interface(decode:, ..)) -> decode(input)
    Error(Nil) -> Error(break.UnhandledEffect(label, input))
  }
}

/// Get the effect lift and lower types for a harness.
pub fn types(
  harness: Harness(_, _),
) -> List(#(String, #(t.Type(Int), t.Type(Int)))) {
  list.map(harness, fn(interface) {
    let Interface(name:, lift_type:, lower_type:, ..) = interface
    #(name, #(lift_type, lower_type))
  })
}
