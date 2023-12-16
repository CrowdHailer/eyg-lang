pub type Program {
  // constraints are facts (without a body) or rules
  // percival calls all constraints rules
  Program(constraints: List(Constraint))
}

pub type Constraint {
  Constraint(head: Atom, body: List(#(Bool, Atom)))
}

// Atoms are also caused Literals maybe goals
pub type Atom {
  Atom(relation: String, terms: List(Term))
}

pub type Term {
  Literal(value: Value)
  Variable(label: String)
}

// TODO join programs
// Map reference

pub type Value {
  B(Bool)
  S(String)
  I(Int)
}
