import gleam/list
if javascript {
  pub external fn concat(String, String) -> String =
    "" "String.prototype.concat.call"
}


pub fn join(parts) {
  list.fold(parts, "", fn(next, buffer) { concat(buffer, next) })
}