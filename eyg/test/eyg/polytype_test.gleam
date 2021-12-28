// move to where state lives TODO
import eyg/typer
import eyg/typer/polytype.{Polytype, instantiate}
import eyg/typer/monotype.{Binary, Function, Tuple, Unbound}

pub fn instantiate_term_test() {
  let polytype = Polytype([], Binary)
  let #(Binary, _) = instantiate(polytype, 1)
}

pub fn instantiate_function_test() {
  let checker = typer.init()
  let polytype = Polytype([0], Function(Unbound(0), Unbound(0)))
  let #(Function(from, to), _) = instantiate(polytype, 1)
  let Unbound(1) = from
  let Unbound(1) = to
}
