import eygir/expression as e
import eyg/parse/lexer
import eyg/parse/parser
import gleeunit/should

pub fn literal_test() {
  "x"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Variable("x"))

  "12"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Integer(12))

  "\"hello\""
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Str("hello"))
}

pub fn lambda_test() {
  // Stop supporting
  // "x -> 5"
  // |> lexer.lex()
  // |> parser.parse()
  // |> should.be_ok()
  // |> should.equal(e.Lambda("x", e.Integer(5)))

  // need brackets otherwise `(f) -> f(3)` is ambiguous `(f) -> { f(3) }` `(f) -> { f }(3)`
  "(x) -> { 5 }"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Lambda("x", e.Integer(5)))

  "(x, y) -> { 5 }"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Lambda("x", e.Lambda("y", e.Integer(5))))
}

// Need a way to mark body

pub fn fn_pattern_test() {
  // Need both brackets if allowing multiple args
  "({x: a, y: b}) -> { 5 }"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Lambda(
    "$",
    e.Let(
      "a",
      e.Apply(e.Select("x"), e.Variable("$")),
      e.Let("b", e.Apply(e.Select("y"), e.Variable("$")), e.Integer(5)),
    ),
  ))
}

pub fn apply_test() {
  "a(1)"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(e.Variable("a"), e.Integer(1)))

  "a(10)(20)"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(
    e.Apply(e.Variable("a"), e.Integer(10)),
    e.Integer(20),
  ))

  "x(y(3))"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(
    e.Variable("x"),
    e.Apply(e.Variable("y"), e.Integer(3)),
  ))
}

pub fn multiple_apply_test() {
  "a(x, y)"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(
    e.Apply(e.Variable("a"), e.Variable("x")),
    e.Variable("y"),
  ))
}

pub fn let_test() -> Nil {
  "let x = 5
   x"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Let("x", e.Integer(5), e.Variable("x")))

  "let x = 5
   x.foo"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Let(
    "x",
    e.Integer(5),
    e.Apply(e.Select("foo"), e.Variable("x")),
  ))

  "let x =
    let y = 3
    y
   x"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Let(
    "x",
    e.Let("y", e.Integer(3), e.Variable("y")),
    e.Variable("x"),
  ))

  "let x = 5
    let y = 1
   x"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Let(
    "x",
    e.Integer(5),
    e.Let("y", e.Integer(1), e.Variable("x")),
  ))
}

pub fn let_record_test() -> Nil {
  "let {x: a, y: _} = rec
   a"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Let(
    "$",
    e.Variable("rec"),
    e.Let(
      "a",
      e.Apply(e.Select("x"), e.Variable("$")),
      e.Let("_", e.Apply(e.Select("y"), e.Variable("$")), e.Variable("a")),
    ),
  ))

  "let {x, y} = rec
   a"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Let(
    "$",
    e.Variable("rec"),
    e.Let(
      "x",
      e.Apply(e.Select("x"), e.Variable("$")),
      e.Let("y", e.Apply(e.Select("y"), e.Variable("$")), e.Variable("a")),
    ),
  ))

  "let {} = rec
   a"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Let("$", e.Variable("rec"), e.Variable("a")))
}

pub fn list_test() {
  "[]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Tail)

  "[1, 2]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.list([e.Integer(1), e.Integer(2)]))

  "[[11]]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.list([e.list([e.Integer(11)])]))

  "[a(7), 8]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(
    e.list([e.Apply(e.Variable("a"), e.Integer(7)), e.Integer(8)]),
  )
}

pub fn list_spread_test() {
  "[1, ..x]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(e.Apply(e.Cons, e.Integer(1)), e.Variable("x")))

  "[1, ..x(5)]"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(
    e.Apply(e.Cons, e.Integer(1)),
    e.Apply(e.Variable("x"), e.Integer(5)),
  ))
}

pub fn record_test() {
  "{}"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Empty)

  "{a: 5, b: {}}"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.record([#("a", e.Integer(5)), #("b", e.Empty)]))

  "{foo: x(2)}"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.record([#("foo", e.Apply(e.Variable("x"), e.Integer(2)))]))
}

pub fn record_sugar_test() {
  "{a, b}"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.record([#("a", e.Variable("a")), #("b", e.Variable("b"))]))
}

pub fn overwrite_test() -> Nil {
  "{a: 5, ..x}"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(
    e.Apply(e.Overwrite("a"), e.Integer(5)),
    e.Variable("x"),
  ))

  "{..x}"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Variable("x"))
}

pub fn overwrite_sugar_test() -> Nil {
  "{a, ..x}"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(
    e.Apply(e.Overwrite("a"), e.Variable("a")),
    e.Variable("x"),
  ))
}

pub fn field_access_test() {
  "a.foo"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(e.Select("foo"), e.Variable("a")))

  "b(x).foo"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(
    e.Select("foo"),
    e.Apply(e.Variable("b"), e.Variable("x")),
  ))

  "a.foo(2)"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(
    e.Apply(e.Select("foo"), e.Variable("a")),
    e.Integer(2),
  ))
}

pub fn tagged_test() {
  "Ok(2)"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(e.Tag("Ok"), e.Integer(2)))
}

pub fn match_test() {
  "match { }"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.NoCases)

  "match x { }"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(e.NoCases, e.Variable("x")))

  "match {
    Ok x
    Error(y) -> { y }
  }"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(
    e.Apply(e.Case("Ok"), e.Variable("x")),
    e.Apply(e.Apply(e.Case("Error"), e.Lambda("y", e.Variable("y"))), e.NoCases),
  ))

  "match {
    User({name, age}) -> { age }
  }"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(
    e.Apply(
      e.Case("User"),
      e.Lambda(
        "$",
        e.Let(
          "name",
          e.Apply(e.Select("name"), e.Variable("$")),
          e.Let(
            "age",
            e.Apply(e.Select("age"), e.Variable("$")),
            e.Variable("age"),
          ),
        ),
      ),
    ),
    e.NoCases,
  ))
}

pub fn perform_test() {
  "perform Log"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Perform("Log"))

  "perform Log(\"stop\")"
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
  |> should.equal(e.Apply(e.Perform("Log"), e.Str("stop")))
}
