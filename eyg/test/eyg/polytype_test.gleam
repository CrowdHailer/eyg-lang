// move to where state lives TODO
import eyg/typer
import eyg/typer/polytype.{Polytype, instantiate}
import eyg/typer/monotype.{Binary, Function, Tuple, Unbound}

pub fn instantiate_term_test() {
  let polytype = Polytype([], Binary)
  let #(Binary, _) = instantiate(polytype, 1)
}

pub fn instantiate_function_test() {
  // these don't error I think the typer should be concerened only with types. not rendering
  let checker = typer.init()
  let polytype = Polytype([0], Function(Unbound(0), Unbound(0)))
  let #(Function(from, to), _) = instantiate(polytype, 1)
  assert Unbound(1) = from
  assert Unbound(1) = to
}
