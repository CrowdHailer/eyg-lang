//// Line based differences between two texts, using Myers' algorithm.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/string

pub type Edit {
  Keep(line: String)
  Insert(line: String)
  Delete(line: String)
}

/// A group of edits with surrounding unchanged lines.
pub type Hunk {
  Hunk(
    old_start: Int,
    old_count: Int,
    new_start: Int,
    new_count: Int,
    edits: List(Edit),
  )
}

/// Differences above this size, after removing a common prefix and suffix,
/// are shown as every old line removed and every new line added.
const limit = 4_000_000

pub fn lines(old: String, new: String) -> List(Edit) {
  edits(split(old), split(new))
}

/// The lines of a text, a final newline does not start another line.
pub fn split(text: String) -> List(String) {
  case text {
    "" -> []
    _ -> {
      let lines = string.split(text, "\n")
      case list.reverse(lines) {
        ["", ..rest] -> list.reverse(rest)
        _ -> lines
      }
    }
  }
}

pub fn edits(old: List(String), new: List(String)) -> List(Edit) {
  let #(prefix, old, new) = common_prefix(old, new, [])
  let #(suffix, old, new) = common_suffix(old, new)
  let middle = case list.length(old) * list.length(new) > limit {
    True -> list.append(list.map(old, Delete), list.map(new, Insert))
    False -> myers(old, new)
  }
  list.flatten([list.map(prefix, Keep), middle, list.map(suffix, Keep)])
}

fn common_prefix(a, b, acc) {
  case a, b {
    [x, ..a_rest], [y, ..b_rest] if x == y ->
      common_prefix(a_rest, b_rest, [x, ..acc])
    _, _ -> #(list.reverse(acc), a, b)
  }
}

fn common_suffix(a, b) {
  let #(suffix, a, b) = common_prefix(list.reverse(a), list.reverse(b), [])
  #(list.reverse(suffix), list.reverse(a), list.reverse(b))
}

fn index(items: List(String)) -> Dict(Int, String) {
  list.index_fold(items, dict.new(), fn(acc, item, i) {
    dict.insert(acc, i, item)
  })
}

fn myers(old: List(String), new: List(String)) -> List(Edit) {
  let a = index(old)
  let b = index(new)
  let n = dict.size(a)
  let m = dict.size(b)
  case n, m {
    0, 0 -> []
    0, _ -> list.map(new, Insert)
    _, 0 -> list.map(old, Delete)
    _, _ -> {
      let trace = search(a, b, n, m, 0, dict.from_list([#(1, 0)]), [])
      backtrack(a, b, trace, n, m, [])
    }
  }
}

// The furthest x reached on each diagonal k, for each number of edits d.
// The trace is kept newest first.
fn search(a, b, n, m, d, v, trace) {
  let trace = [v, ..trace]
  case step(a, b, n, m, d, -d, v) {
    Ok(_) -> trace
    Error(v) -> search(a, b, n, m, d + 1, v, trace)
  }
}

fn step(a, b, n, m, d, k, v) -> Result(Nil, Dict(Int, Int)) {
  case k > d {
    True -> Error(v)
    False -> {
      let x = case k == -d || { k != d && get(v, k - 1) < get(v, k + 1) } {
        True -> get(v, k + 1)
        False -> get(v, k - 1) + 1
      }
      let x = snake(a, b, n, m, x, x - k)
      let v = dict.insert(v, k, x)
      case x >= n && x - k >= m {
        True -> Ok(Nil)
        False -> step(a, b, n, m, d, k + 2, v)
      }
    }
  }
}

fn snake(a, b, n, m, x, y) {
  case x < n && y < m && dict.get(a, x) == dict.get(b, y) {
    True -> snake(a, b, n, m, x + 1, y + 1)
    False -> x
  }
}

fn get(v, k) {
  case dict.get(v, k) {
    Ok(x) -> x
    Error(Nil) -> 0
  }
}

fn backtrack(a, b, trace, x, y, acc) {
  case trace {
    [] -> acc
    [v, ..rest] -> {
      let d = list.length(rest)
      let k = x - y
      let previous_k = case
        k == -d || { k != d && get(v, k - 1) < get(v, k + 1) }
      {
        True -> k + 1
        False -> k - 1
      }
      let previous_x = get(v, previous_k)
      let previous_y = previous_x - previous_k
      let #(x, y, acc) = diagonal(a, x, y, previous_x, previous_y, acc)
      let acc = case d > 0 {
        False -> acc
        True ->
          case x == previous_x {
            True -> [Insert(line(b, y - 1)), ..acc]
            False -> [Delete(line(a, x - 1)), ..acc]
          }
      }
      backtrack(a, b, rest, previous_x, previous_y, acc)
    }
  }
}

fn diagonal(a, x, y, previous_x, previous_y, acc) {
  case x > previous_x && y > previous_y {
    True ->
      diagonal(a, x - 1, y - 1, previous_x, previous_y, [
        Keep(line(a, x - 1)),
        ..acc
      ])
    False -> #(x, y, acc)
  }
}

fn line(lines, i) {
  case dict.get(lines, i) {
    Ok(line) -> line
    Error(Nil) -> ""
  }
}

/// The number of lines added and removed.
pub fn stats(edits: List(Edit)) -> #(Int, Int) {
  list.fold(edits, #(0, 0), fn(acc, edit) {
    case edit {
      Keep(_) -> acc
      Insert(_) -> #(acc.0 + 1, acc.1)
      Delete(_) -> #(acc.0, acc.1 + 1)
    }
  })
}

/// Group edits into hunks with `context` unchanged lines around each change.
pub fn hunks(edits: List(Edit), context: Int) -> List(Hunk) {
  let numbered = number(edits, 1, 1, [])
  let total = list.length(numbered)
  let changed =
    list.index_fold(numbered, [], fn(acc, item, i) {
      case item.2 {
        Keep(_) -> acc
        _ -> [i, ..acc]
      }
    })
    |> list.reverse
  group(changed, context, [])
  |> list.map(fn(range) {
    let #(from, to) = range
    let from = int.max(0, from - context)
    let to = int.min(total - 1, to + context)
    let items = numbered |> list.drop(from) |> list.take(to - from + 1)
    let assert [#(old_start, new_start, _), ..] = items
    let edits = list.map(items, fn(item) { item.2 })
    let old_count =
      list.count(edits, fn(edit) {
        case edit {
          Insert(_) -> False
          _ -> True
        }
      })
    let new_count =
      list.count(edits, fn(edit) {
        case edit {
          Delete(_) -> False
          _ -> True
        }
      })
    Hunk(old_start:, old_count:, new_start:, new_count:, edits:)
  })
}

// Each edit with the old and new line number it is at.
fn number(edits, old, new, acc) {
  case edits {
    [] -> list.reverse(acc)
    [edit, ..rest] -> {
      let acc = [#(old, new, edit), ..acc]
      case edit {
        Keep(_) -> number(rest, old + 1, new + 1, acc)
        Insert(_) -> number(rest, old, new + 1, acc)
        Delete(_) -> number(rest, old + 1, new, acc)
      }
    }
  }
}

// Merge changed positions closer than twice the context into ranges.
fn group(changed, context, acc) {
  case changed, acc {
    [], _ -> list.reverse(acc)
    [i, ..rest], [#(from, to), ..ranges] if i - to <= 2 * context ->
      group(rest, context, [#(from, i), ..ranges])
    [i, ..rest], _ -> group(rest, context, [#(i, i), ..acc])
  }
}

/// A unified diff of two texts.
pub fn unified(old: String, new: String, context: Int) -> String {
  hunks(lines(old, new), context)
  |> list.map(fn(hunk) {
    let Hunk(old_start:, old_count:, new_start:, new_count:, edits:) = hunk
    let header =
      "@@ -"
      <> range(old_start, old_count)
      <> " +"
      <> range(new_start, new_count)
      <> " @@"
    [
      header,
      ..list.map(edits, fn(edit) {
        case edit {
          Keep(line) -> " " <> line
          Insert(line) -> "+" <> line
          Delete(line) -> "-" <> line
        }
      })
    ]
    |> string.join("\n")
  })
  |> string.join("\n")
}

fn range(start, count) {
  case count {
    0 -> int.to_string(start - 1) <> ",0"
    1 -> int.to_string(start)
    _ -> int.to_string(start) <> "," <> int.to_string(count)
  }
}
