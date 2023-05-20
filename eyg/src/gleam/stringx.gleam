import gleam/listx
import gleam/string

pub fn insert_at(original, at, new) {
  string.to_graphemes(original)
  |> listx.insert_at(at, string.to_graphemes(new))
  |> string.concat
}
