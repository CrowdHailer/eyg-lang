import eyg/parser
import gleam/io
import gleam/list
import morph/editable
import morph/navigation

const lists =
  "let a = []
let b = [1, \"\", {}]
let nested = [[[]], [a, b]]
let c = [2, 3, ..a]
let end = 
  let d = 4
  []
let end = 
  let e = 5
  [7, 8, ..a]
[[]]
"

const record_construction =
  "let a = {}
let b = {foo: 1, bar: \"\", a}
let nested = {x: {y: {}}, z: {foo: 1, bar: \"\", a}}
let end = 
  let d = 5
  {}
{foo: 1, bar: \"\", a}
"

const record_override =
  "let a = {..todo}
{x: 5, y, nested: {x, ..another}, ..original}"

fn predefined(then) {
  [lists, record_construction, record_override]
  |> list.each(fn(code) {
    case parser.all_from_string(code) {
      Ok(source) -> then(editable.open_all(editable.from_annotated(source)))
      Error(reason) -> {
        io.println(parser.format_error(reason, code))
        panic
      }
    }
  })
}

fn walk_leaves(editable) {
  let first = navigation.first(editable)
  do_walk_leaves(first, [first])
}

fn do_walk_leaves(current, seen) {
  let next = navigation.next(current)
  case list.contains(seen, next) {
    True -> list.reverse(seen)
    False -> do_walk_leaves(next, [next, ..seen])
  }
}

pub fn left_right_returns_to_starting_projection_test() {
  use program <- predefined
  use leaf <- list.each(walk_leaves(program))
  assert leaf == navigation.previous(navigation.next(leaf))
}
