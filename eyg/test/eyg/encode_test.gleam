import eyg/ast
import eyg/ast/expression as e
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
  assert True = tree == round_trip(tree)
}

pub fn encode_tuple_test() {
  let tree = ast.tuple_([ast.tuple_([]), ast.binary("Example")])
  assert True = tree == round_trip(tree)
}

pub fn encode_record_test() {
  let tree = ast.record([#("foo", ast.record([])), #("bar", ast.binary("Bar"))])
  assert True = tree == round_trip(tree)
}

pub fn encode_tagged_test() {
  let tree = e.tagged("Foo", ast.tuple_([]))
  assert True = tree == round_trip(tree)
}

pub fn encode_variable_test() {
  let tree = ast.variable("var")
  assert True = tree == round_trip(tree)
}

pub fn encode_let_test() {
  let tree =
    ast.let_(
      p.Variable("foo"),
      ast.tuple_([]),
      ast.let_(
        p.Tuple(["bar", ""]),
        ast.tuple_([]),
        ast.let_(p.Record([#("baz", "b")]), ast.tuple_([]), ast.variable("foo")),
      ),
    )

  assert True = tree == round_trip(tree)
}

pub fn encode_function_test() {
  let tree = ast.function(p.Variable("x"), ast.variable("x"))
  assert True = tree == round_trip(tree)
}

pub fn encode_call_test() {
  let tree = ast.call(ast.variable("x"), ast.tuple_([]))
  assert True = tree == round_trip(tree)
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
  assert True = tree == round_trip(tree)
}

pub fn encode_hole_test() {
  let tree = ast.hole()
  assert True = tree == round_trip(tree)
}
