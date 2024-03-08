import gleam/io
import gleam/option.{None}
import morph/editable as e
import morph/projection as t
import eyg/parse
import gleeunit/should

// a children function that is then indexed is inefficient.
// testing each index in turn only work if the list tail is not called 0

pub fn from_string(source) {
  source
  |> parse.from_string()
  |> should.be_ok()
  // |> io.debug
  |> e.from_annotated()
}

pub fn focus_at(source, path) {
  t.focus_at(source, path, [])
}

pub fn rebuild(scope) {
  case scope {
    #(t.Exp(e), []) -> e
    _ -> rebuild(should.be_ok(t.step(scope)))
  }
}

pub fn let_test_test() {
  let source =
    "let a = 1
    let b =
      let x = \"hello\"
      x
    b"
    |> from_string()

  let scope = focus_at(source, [1, 1, 0, 1])
  scope.0
  |> should.equal(t.Exp(e.String("hello")))

  let scope = should.be_ok(t.step(scope))
  scope
  |> should.equal(focus_at(source, [1, 1, 0]))

  let scope = should.be_ok(t.step(scope))
  scope
  |> should.equal(focus_at(source, [1, 1]))
}

pub fn list_test() {
  let source =
    "[
      let x = []
      x,
      [1, 2],
      [3,..y]
    ]"
    |> from_string()
  let scope = focus_at(source, [1, 1])
  scope.0
  |> should.equal(t.Exp(e.Integer(2)))
  rebuild(scope)
  |> should.equal(source)

  let scope = focus_at(source, [2, 1])
  scope.0
  |> should.equal(t.Exp(e.Variable("y")))
  rebuild(scope)
  |> should.equal(source)
}

pub fn record_test() {
  let source =
    "{
      foo: {},
      bar: 1
    }"
    |> from_string()
  let scope = focus_at(source, [0, 1])
  scope.0
  |> should.equal(t.Exp(e.Record([], None)))
  rebuild(scope)
  |> should.equal(source)

  let scope = focus_at(source, [1, 0])
  scope.0
  |> should.equal(t.Label(
    "bar",
    e.Integer(1),
    [#("foo", e.Record([], None))],
    [],
    t.Record,
  ))
  rebuild(scope)
  |> should.equal(source)
}

pub fn let_pattern_test() {
  let source =
    "let {x, y: a} = {}
    a"
    |> from_string()

  let scope = focus_at(source, [0, 0, 3])
  scope.0
  |> should.equal(t.Exp(e.Record([], None)))
}

pub fn case_test() {
  let source =
    "match x {
      Ok(y) -> { y }
      | (_) -> { 2 }
    }"
    |> from_string()
  let scope = focus_at(source, [0])
  scope.0
  |> should.equal(t.Exp(e.Variable("x")))
  rebuild(scope)
  |> should.equal(source)

  let scope = focus_at(source, [1, 0])
  scope.0
  |> should.equal(t.Exp(e.Function([e.Bind("y")], e.Variable("y"))))
  rebuild(scope)
  |> should.equal(source)
}
