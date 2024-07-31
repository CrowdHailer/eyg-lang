import eyg/parse
import gleam/option.{None}
import gleam/pair
import gleeunit/should
import morph/editable as e
import morph/projection as p

pub fn from_string(source) {
  source
  |> parse.from_string()
  |> should.be_ok()
  |> pair.first()
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
    "let a = 1
    let b =
      let x = \"hello\"
      x
    b"
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
    "[
      let x = []
      x,
      [1, 2],
      [3,..y]
    ]"
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
    "{
      foo: {},
      bar: 1
    }"
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
    "let {x, y: a} = {}
    a"
    |> from_string()

  let scope = p.focus_at(source, [0, 1])
  scope.0
  |> should.equal(p.Exp(e.Record([], None)))
}

pub fn case_test() {
  let source =
    "match x {
      Ok(y) -> { y }
      | (_) -> { 2 }
    }"
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
