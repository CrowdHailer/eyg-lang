import gleam/io
import gleam/option.{Option}

pub type Monotype {
  Binary
  Tuple(elements: List(Monotype))
  Row(fields: List(#(String, Monotype)), extra: Option(Int))
  Nominal(name: String, of: List(Monotype))
  Function(from: Monotype, to: Monotype)
  Unbound(i: Int)
}

pub type Unification {
  Unification(next_unbound: Int, substitutions: List(#(Int, Monotype)))
}

pub fn checker() {
  Unification(0, [])
}

pub fn next_unbound(state) {
  io.debug(state)
  let Unification(next_unbound: i, ..) = state
  let state = Unification(..state, next_unbound: i + 1)
  #(i, state)
}
