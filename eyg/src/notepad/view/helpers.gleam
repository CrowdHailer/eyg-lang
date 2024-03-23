import gleam/int
import gleam/list
import gleam/string

pub fn line_count(content) {
  string.split(content, "\n")
  |> list.length
  // string as used in attributes
  |> int.to_string
}
