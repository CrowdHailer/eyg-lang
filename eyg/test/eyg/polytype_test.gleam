// move to where state lives TODO
import eyg/typer
import eyg/typer/polytype.{Polytype, instantiate, next_unbound}
import eyg/typer/monotype.{Binary, Function, Tuple, Unbound}

// TODO move
fn init(variables) {
  polytype.State(variables, 0, [], [])
}

pub fn instantiate_term_test() {
  let polytype = Polytype([], Binary)
  let #(Binary, _) = instantiate(polytype, init([]))
}

pub fn instantiate_function_test() {
  let checker = init([])
  let #(0, checker) = next_unbound(checker)
  let polytype = Polytype([0], Function(Unbound(0), Unbound(0)))
  let #(Function(from, to), _) = instantiate(polytype, checker)
  let Unbound(1) = from
  let Unbound(1) = to
}

pub fn instantiate_nested_function_test() {
  let checker = init([])
  let #(0, checker) = next_unbound(checker)
  let polytype = Polytype([0], Function(Unbound(0), Tuple([Unbound(0)])))
  let #(Function(from, to), _) = instantiate(polytype, checker)
  let Unbound(1) = from
  let Tuple([Unbound(1)]) = to
}
