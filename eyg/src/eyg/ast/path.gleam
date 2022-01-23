import gleam/list
import gleam/order

pub fn root() {
  []
}

// maybe path.child
pub fn append(path, i) {
  list.append(path, [i])
}

pub fn parent(path) {
  case list.reverse(path) {
    [] -> Error(Nil)
    [last, ..rest] -> Ok(#(list.reverse(rest), last))
  }
}

pub fn order(a, b) {
  case a, b {
    [], [] -> order.Eq
    [x, .._], [y, .._] if x < y -> order.Lt
    [x, .._], [y, .._] if x > y -> order.Gt
    [], [_, .._] -> order.Lt
    [_, .._], [] -> order.Gt
    [x, ..a], [y, ..b] if x == y -> order(a, b)
  }
}
