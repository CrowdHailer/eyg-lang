import gleam/io
import gleam/list
import gleam/string
import language/ast.{Assignment as Var, Destructure}
import language/ast/builder.{
  binary, call, case_, constructor as variant, destructure_tuple, row, tuple_, varient as name,
}
import language/scope
import language/type_.{Data, Variable}
import eyg/helpers.{fun, label_call, seq, test, var, vars}

fn move_all() {
  fun(
    "move_all",
    ["remaining", "reversed"],
    [],
    case_(
      var("remaining"),
      [
        #(
          Destructure("Cons", ["next", "remaining"]),
          call(
            var("self"),
            [
              var("remaining"),
              call(var("Cons"), [var("next"), var("reversed")]),
            ],
          ),
        ),
        #(Destructure("Nil", []), var("reversed")),
      ],
    ),
  )
}

fn reverse() {
  fun(
    "reverse",
    ["input"],
    [],
    call(var("move_all"), [var("input"), call(var("Nil"), [])]),
  )
}

fn append() {
  fun(
    "append",
    ["first", "second"],
    [#(Var("reversed"), label_call("reverse", ["first"]))],
    label_call("move_all", ["reversed", "second"]),
  )
}

fn do_map() {
  fun(
    "do_map",
    ["input", "func", "acc"],
    [],
    case_(
      var("input"),
      [
        #(
          Destructure("Cons", ["next", "remaining"]),
          seq(
            [
              #(Var("mapped"), label_call("func", ["next"])),
              #(Var("acc"), label_call("Cons", ["mapped", "acc"])),
            ],
            label_call("self", ["remaining", "func", "acc"]),
          ),
        ),
        #(Destructure("Nil", []), call(var("reverse"), [var("acc")])),
      ],
    ),
  )
}

fn map() {
  fun(
    "map",
    ["input", "func"],
    [#(Var("empty"), call(var("Nil"), []))],
    label_call("do_map", ["input", "func", "empty"]),
  )
}

fn key_find() {
  fun(
    "key_find",
    ["list", "search"],
    [],
    case_(
      var("list"),
      [
        #(
          Destructure("Cons", ["next", "list"]),
          destructure_tuple(
            ["key", "value"],
            var("next"),
            case_(
              call(var("equal"), [var("key"), var("search")]),
              [
                #(Destructure("True", []), call(var("Ok"), [var("value")])),
                #(
                  Destructure("False", []),
                  call(var("self"), [var("list"), var("key")]),
                ),
              ],
            ),
          ),
        ),
        #(Destructure("Nil", []), call(var("Error"), [call(var("Nil"), [])])),
      ],
    ),
  )
}

pub fn exports() {
  ["Cons", "Nil", "reverse", "append", "map", "key_find"]
}

fn boolean(then) {
  name("Boolean", [], [variant("True", []), variant("False", [])], then)
}

fn result(then) {
  boolean(name(
    "Result",
    [1, 2],
    [variant("Ok", [Variable(1)]), variant("Error", [Variable(2)])],
    then,
  ))
}

pub fn code() {
  // Nominal/Named
  name(
    "List",
    [1],
    [
      variant("Cons", [Variable(1), Data("List", [Variable(1)])]),
      variant("Nil", []),
    ],
    seq(
      [move_all(), reverse(), append(), do_map(), map(), key_find()],
      tuple_(vars(exports())),
    ),
  )
}

pub fn load(then) {
  result(destructure_tuple(
    list.map(exports(), fn(f) { string.concat(["list$", f]) }),
    code(),
    then,
  ))
}

pub fn tests() {
  let all_tests = [
    test(
      "reverse",
      [#(Var("in"), to_list([binary("1"), binary("2"), binary("3")]))],
      label_call("list$reverse", ["in"]),
    ),
  ]
  let labels =
    list.map(
      all_tests,
      fn(t) {
        let #(Var(label), _) = t
        #(label, var(label))
      },
    )
  // todo this should be a row
  load(seq(all_tests, row(labels)))
}

pub fn to_list(values) {
  list.fold(
    list.reverse(values),
    label_call("list$Nil", []),
    fn(value, previous) { call(var("list$Cons"), [value, previous]) },
  )
}
