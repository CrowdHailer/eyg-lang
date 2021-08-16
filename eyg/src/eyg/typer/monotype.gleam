import gleam/option.{Option}

pub type Monotype {
  Binary
  Tuple(elements: List(Monotype))
  Row(fields: List(#(String, Monotype)), extra: Option(Int))
  Nominal(name: String, of: List(Monotype))
  Function(from: Monotype, to: Monotype)
  Unbound(i: Int)
}
