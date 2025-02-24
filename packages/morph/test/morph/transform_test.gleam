import eyg/ir/dag_json
import gleam/bit_array
import gleam/option.{None}
import gleeunit/should
import morph/editable as e
import morph/projection as p

pub fn from_string(source) {
  source
  |> bit_array.from_string()
  |> dag_json.from_block()
  |> should.be_ok()
  |> e.from_annotated()
}

pub fn rebuild(scope) {
  case scope {
    #(p.Exp(e), []) -> e
    _ -> rebuild(should.be_ok(p.step(scope)))
  }
}

pub fn let_test() {
  let source =
    "{\"0\":\"l\",\"l\":\"a\",\"t\":{\"0\":\"l\",\"l\":\"b\",\"t\":{\"0\":\"v\",\"l\":\"b\"},\"v\":{\"0\":\"l\",\"l\":\"x\",\"t\":{\"0\":\"v\",\"l\":\"x\"},\"v\":{\"0\":\"s\",\"v\":\"hello\"}}},\"v\":{\"0\":\"i\",\"v\":1}}"
    |> from_string()
    |> e.open_all

  let scope = p.focus_at(source, [1, 1, 0, 1])
  scope.0
  |> should.equal(p.Exp(e.String("hello")))

  let scope = should.be_ok(p.step(scope))
  scope
  |> should.equal(p.focus_at(source, [1, 1, 0]))

  let scope = should.be_ok(p.step(scope))
  scope
  |> should.equal(p.focus_at(source, [1, 1]))
}

pub fn list_test() {
  let source =
    "{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"ta\"},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"v\",\"l\":\"y\"},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"i\",\"v\":3},\"f\":{\"0\":\"c\"}}},\"f\":{\"0\":\"c\"}}},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"ta\"},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"i\",\"v\":2},\"f\":{\"0\":\"c\"}}},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"i\",\"v\":1},\"f\":{\"0\":\"c\"}}},\"f\":{\"0\":\"c\"}}},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"l\",\"l\":\"x\",\"t\":{\"0\":\"v\",\"l\":\"x\"},\"v\":{\"0\":\"ta\"}},\"f\":{\"0\":\"c\"}}}"
    |> from_string()
  let scope = p.focus_at(source, [1, 1])
  scope.0
  |> should.equal(p.Exp(e.Integer(2)))
  rebuild(scope)
  |> should.equal(source)

  let scope = p.focus_at(source, [2, 1])
  scope.0
  |> should.equal(p.Exp(e.Variable("y")))
  rebuild(scope)
  |> should.equal(source)
}

pub fn record_test() {
  let source =
    "{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"u\"},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"i\",\"v\":1},\"f\":{\"0\":\"e\",\"l\":\"bar\"}}},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"u\"},\"f\":{\"0\":\"e\",\"l\":\"foo\"}}}"
    |> from_string()
  let scope = p.focus_at(source, [1])
  scope.0
  |> should.equal(p.Exp(e.Record([], None)))
  rebuild(scope)
  |> should.equal(source)

  let scope = p.focus_at(source, [2])
  scope.0
  |> should.equal(p.Label(
    "bar",
    e.Integer(1),
    [#("foo", e.Record([], None))],
    [],
    p.Record,
  ))
  rebuild(scope)
  |> should.equal(source)
}

pub fn let_pattern_test() {
  let source =
    "{\"0\":\"l\",\"l\":\"$\",\"t\":{\"0\":\"l\",\"l\":\"x\",\"t\":{\"0\":\"l\",\"l\":\"a\",\"t\":{\"0\":\"v\",\"l\":\"a\"},\"v\":{\"0\":\"a\",\"a\":{\"0\":\"v\",\"l\":\"$\"},\"f\":{\"0\":\"g\",\"l\":\"y\"}}},\"v\":{\"0\":\"a\",\"a\":{\"0\":\"v\",\"l\":\"$\"},\"f\":{\"0\":\"g\",\"l\":\"x\"}}},\"v\":{\"0\":\"u\"}}"
    |> from_string()

  let scope = p.focus_at(source, [0, 1])
  scope.0
  |> should.equal(p.Exp(e.Record([], None)))
}

pub fn case_test() {
  let source =
    "{\"0\":\"a\",\"a\":{\"0\":\"v\",\"l\":\"x\"},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"f\",\"b\":{\"0\":\"i\",\"v\":2},\"l\":\"_\"},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"f\",\"b\":{\"0\":\"v\",\"l\":\"y\"},\"l\":\"y\"},\"f\":{\"0\":\"m\",\"l\":\"Ok\"}}}}"
    |> from_string()
  let scope = p.focus_at(source, [0])
  scope.0
  |> should.equal(p.Exp(e.Variable("x")))
  rebuild(scope)
  |> should.equal(source)

  let scope = p.focus_at(source, [1, 0])
  scope.0
  |> should.equal(p.Exp(e.Function([e.Bind("y")], e.Variable("y"))))
  rebuild(scope)
  |> should.equal(source)
}
