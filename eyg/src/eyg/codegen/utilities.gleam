import gleam/list
import gleam/string

pub fn indent(lines) {
  list.map(lines, fn(line) { string.concat("  ", line) })
}

pub fn wrap_lines(pre, lines, post) {
  case lines {
    [] -> [string.concat(pre, post)]
    [first, ..rest] -> {
      let first = string.concat(pre, first)
      let lines = [first, ..rest]
      let [last, ..rest] = list.reverse(lines)
      let last = string.concat(last, post)
      list.reverse([last, ..rest])
    }
  }
}
