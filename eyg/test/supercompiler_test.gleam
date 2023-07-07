import gleam/io
import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eygir/expression as e
import eyg/supercompiler.{eval}
import gleeunit/should

pub fn supercompiler_test() {
  let #(exp, values) = eval(e.Let("x", e.Binary("hello"), e.Variable("x")))
  exp
  |> should.equal(e.Binary("hello"))

  let #(exp, values) =
    eval(e.Apply(e.Lambda("_", e.Binary("hello")), e.Binary("ignore")))
  exp
  |> should.equal(e.Binary("hello"))

  let #(exp, values) =
    eval(e.Apply(e.Lambda("x", e.Variable("x")), e.Binary("hello")))
  exp
  |> should.equal(e.Binary("hello"))

  let #(exp, values) =
    eval(e.Apply(e.Builtin("string_uppercase"), e.Binary("hello")))
  exp
  |> should.equal(e.Binary("HELLO"))
}

pub fn reduce_body_test() {
  let #(exp, values) =
    eval(e.Let(
      "x",
      e.Integer(-1),
      e.Lambda("_", e.Apply(e.Builtin("integer_absolute"), e.Variable("x"))),
    ))
  exp
  |> should.equal(e.Lambda("_", e.Integer(1)))
}

pub fn shadowing_in_function_test() {
  let #(exp, values) =
    eval(e.Let("x", e.Integer(5), e.Lambda("x", e.Variable("x"))))
  exp
  |> should.equal(e.Lambda("x", e.Variable("x")))
}

pub fn collapse_part_in_apply_test() {
  let #(exp, values) =
    eval(e.Lambda(
      "x",
      e.Apply(
        e.Apply(e.Builtin("integer_add"), e.Variable("x")),
        e.Apply(e.Apply(e.Builtin("integer_add"), e.Integer(2)), e.Integer(3)),
      ),
    ))
  exp
  |> should.equal(e.Lambda(
    "x",
    e.Apply(e.Apply(e.Builtin("integer_add"), e.Variable("x")), e.Integer(5)),
  ))
}

pub fn variable_shadowing_test() {
  let #(exp, values) =
    eval(e.Lambda(
      "y",
      e.Let("x", e.Integer(5), e.Let("x", e.Variable("y"), e.Variable("x"))),
    ))
  exp
  |> should.equal(e.Lambda("y", e.Variable("y")))
}

// in language helper for list
// lang_eval
// check that error is in the right place

pub fn debug_fold_test() {
  let #(exp, values) =
    e.Lambda(
      "list",
      e.Apply(
        e.Apply(e.Apply(e.Builtin("list_fold"), e.Variable("list")), e.Tail),
        e.Lambda(
          "el",
          e.Lambda(
            "acc",
            e.Apply(e.Apply(e.Cons, e.Variable("el")), e.Variable("acc")),
          ),
        ),
      ),
    )
    |> eval()
  // exp
  // |> should.equal(e.Lambda("y", e.Variable("y")))
  // io.debug(
  values
  |> map.to_list
  |> list.sort(fn(a, b) { string.compare(path_to_string(a), path_to_string(b)) })
  |> list.map(fn(x) {
    // io.debug(x)
    io.print(string.concat([
      "\n-------------\n",
      path_to_string(x),
      string.inspect(x.1),
      "\n",
    ]))
  })
  // io.debug(x.1)
  // )
  // todo
}

pub fn path_to_string(path: #(_, _)) {
  // relies on all index being single char
  list.map(path.0, int.to_string)
  |> string.join(",")
}
