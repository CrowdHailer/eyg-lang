import gleam/option.{None, Some}
import eyg/ast
import eyg/ast/encode
import eyg/ast/pattern as p

fn round_trip(ast) {
  ast
  |> encode.to_json
  |> encode.json_to_string
  |> encode.json_from_string
  |> encode.from_json
}

pub fn encode_binary_test() {
  let tree = ast.binary("Example")
  let True = tree == round_trip(tree)
}

pub fn encode_tuple_test() {
  let tree = ast.tuple_([ast.tuple_([]), ast.binary("Example")])
  let True = tree == round_trip(tree)
}

pub fn encode_row_test() {
  let tree = ast.row([#("foo", ast.row([])), #("bar", ast.binary("Bar"))])
  let True = tree == round_trip(tree)
}

pub fn encode_variable_test() {
  let tree = ast.variable("var")
  let True = tree == round_trip(tree)
}

pub fn encode_let_test() {
  let tree =
    ast.let_(
      p.Discard,
      ast.tuple_([]),
      ast.let_(
        p.Variable("foo"),
        ast.tuple_([]),
        ast.let_(
          p.Tuple([Some("bar"), None]),
          ast.tuple_([]),
          ast.let_(p.Row([#("baz", "b")]), ast.tuple_([]), ast.variable("foo")),
        ),
      ),
    )

  let True = tree == round_trip(tree)
}

pub fn encode_function_test() {
  let tree = ast.function(p.Variable("x"), ast.variable("x"))
  let True = tree == round_trip(tree)
}

pub fn encode_call_test() {
  let tree = ast.call(ast.variable("x"), ast.tuple_([]))
  let True = tree == round_trip(tree)
}

pub fn encode_case_test() {
  let tree =
    ast.case_(
      ast.variable("x"),
      [
        #("True", p.Tuple([]), ast.binary("True")),
        #("False", p.Tuple([]), ast.binary("Not")),
      ],
    )
  let True = tree == round_trip(tree)
}

pub fn encode_hole_test() {
  let tree = ast.hole()
  let True = tree == round_trip(tree)
}
