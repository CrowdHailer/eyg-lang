import eygir/expression as e

pub type Action {
  Keypress(key: String)
  SelectNode(path: List(Int))
}
