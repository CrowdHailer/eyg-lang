import gleam/io

pub type Recursive {
  Tree(Recursive, Recursive)
  Leaf
}

// looks ok is there a missing step in fold
fn eval(terms, k) {
  case terms {
    Tree(x, y) -> eval(x, fn(x2) { eval(y, fn(y2) { k(x2 + y2) }) })
    Leaf -> k(1)
  }
}

pub fn something_test() {
  Tree(Tree(Leaf, Leaf), Leaf)
  |> eval(fn(x) { x })
}
