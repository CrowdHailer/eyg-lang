import eygir/expression as e

pub type Action {
  Keypress(key: String)
  SelectNode(path: List(Int))
}

pub type State {
  State(selection: List(Int), source: e.Expression)
}
