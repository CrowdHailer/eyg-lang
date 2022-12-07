import gleam/list
import gleam/set

pub fn singleton(value) {
  set.new()
  |> set.insert(value)
}

pub fn drop(set, nope) {
  list.fold(nope, set, set.delete)
}
