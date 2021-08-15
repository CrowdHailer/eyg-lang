import eyg/typer/monotype.{Monotype}

pub type Polytype {
  Polytype(forall: List(Int), monotype: Monotype)
}

pub fn instantiate(polytype) {
  // TODO handle generalised
  let Polytype([], monotype) = polytype
  monotype
}

pub fn generalise(monotype) {
  // TODO generalise fns
  Polytype([], monotype)
}
