import eyg/typer/polytype.{Polytype, instantiate}
import eyg/typer/monotype as t

pub fn instantiate_term_test() {
  let polytype = Polytype([], t.Binary)
  let #(t.Binary, _) = instantiate(polytype, 1)
}

pub fn instantiate_function_test() {
  let polytype =
    Polytype([0], t.Function(t.Unbound(0), t.Unbound(0), t.Unbound(0)))
  let #(t.Function(from, to, effect), _) = instantiate(polytype, 1)
  assert t.Unbound(1) = from
  assert t.Unbound(1) = to
  assert t.Unbound(1) = effect
}
