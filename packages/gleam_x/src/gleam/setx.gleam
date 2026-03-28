import gleam/set

pub fn singleton(value) {
  set.new()
  |> set.insert(value)
}
