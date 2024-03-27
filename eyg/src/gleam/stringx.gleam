import gleam/list
import gleam/listx
import gleam/string

pub fn insert_at(original, at, new) {
  string.to_graphemes(original)
  |> listx.insert_at(at, string.to_graphemes(new))
  |> string.concat
}

pub fn replace_at(original, from, to, new) {
  let letters = string.to_graphemes(original)
  let pre = list.take(letters, from)
  let post = list.drop(letters, to)
  list.flatten([pre, string.to_graphemes(new), post])
  |> string.concat
}

@external(javascript, "../plinth_ffi.js", "foldGraphmemes")
pub fn fold_graphmemes(a: String, b: a, c: fn(a, String) -> a) -> a

@external(javascript, "../plinth_ffi.js", "foldGraphmemes")
pub fn index_fold_graphmemes(a: String, b: a, c: fn(a, String, Int) -> a) -> a

pub fn wrap(content, pre, post) {
  string.concat([pre, content, post])
}
