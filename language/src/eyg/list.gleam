import gleam/io
import gleam/list
import language/ast.{Assignment as Var, Destructure}
import language/ast/builder.{
  call, case_, constructor, destructure_tuple, tuple_, varient,
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
  ["Cons", "Nil", "reverse", "map", "key_find"]
}

pub fn return_tuple() {
  // Nominal/Named
  varient(
    "List",
    [1],
    [
      constructor("Cons", [Variable(1), Data("List", [Variable(1)])]),
      constructor("Nil", []),
    ],
    seq(
      [move_all(), reverse(), do_map(), map(), key_find()],
      tuple_(vars(exports())),
    ),
  )
}
