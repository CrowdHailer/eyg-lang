import gleam/list
import gleam/order

pub fn root() {
  []
}

pub fn append(path, i) {
  list.append(path, [i])
}

pub fn order(a, b) {
  case a, b {
    [], [] -> order.Eq
    [x, .._], [y, .._] if x < y -> order.Lt
    [x, .._], [y, .._] if x > y -> order.Gt
    [], [y, .._] -> order.Lt
    [x, .._], [] -> order.Gt
    [x, ..a], [y, ..b] if x == y -> order(a, b)
  }
}
