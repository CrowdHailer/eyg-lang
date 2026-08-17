import gleam/list

pub fn push_new(existing, new) {
  case list.contains(existing, new) {
    True -> existing
    False -> [new, ..existing]
  }
}
