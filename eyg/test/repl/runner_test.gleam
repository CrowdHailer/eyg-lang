import gleam/io
import gleam/dict
import gleam/list
import glance
import glexer
import repl/runner.{F, I, L, S, T}
import plinth/javascript/console
import gleeunit/should

fn exec(src) {
  let assert Ok(#(statement, rest)) =
    glexer.new(src)
    |> glexer.lex
    |> list.filter(fn(pair) { !glance.is_whitespace(pair.0) })
    |> glance.statement
  // |> io.debug
  runner.exec(statement, dict.new())
}

pub fn literal_test() {
  "1"
  |> exec()
  |> should.equal(Ok(I(1)))

  "2.0"
  |> exec()
  |> should.equal(Ok(F(2.0)))

  "\"\""
  |> exec()
  |> should.equal(Ok(S("")))

  "\"hello\""
  |> exec()
  |> should.equal(Ok(S("hello")))
//   How do we make sure named arguments go to the right place if using native
  console.log(Ok(""))
  console.log(Ok)
  console.log(runner.I(1))
  console.log(runner.Append([]))
}

pub fn number_negation_test() {
  "-1"
  |> exec()
  |> should.equal(Ok(I(-1)))

  "-1.0"
  |> exec()
  |> should.equal(Ok(F(-1.0)))
}

// pub fn bool_negation_test() {
//   todo
//   //   "!"
//   //   |> exec()
//   //   |> should.equal(Ok(I(-1)))
// }

// todo block

pub fn tuple_test() {
  "#()"
  |> exec()
  |> should.equal(Ok(T([])))

  "#(1, 2.0)"
  |> exec()
  |> should.equal(Ok(T([I(1), F(2.0)])))

  "#(1 + 2)"
  |> exec()
  |> should.equal(Ok(T([I(3)])))
}

pub fn tuple_index_test() {
  "#(1).0"
  |> exec()
  |> should.equal(Ok(I(1)))

  "#(1, 2.0).1"
  |> exec()
  |> should.equal(Ok(F(2.0)))
}

pub fn list_test() {
  "[]"
  |> exec()
  |> should.equal(Ok(L([])))

  "[1, 2.0]"
  |> exec()
  |> should.equal(Ok(L([I(1), F(2.0)])))

  "[1 + 2]"
  |> exec()
  |> should.equal(Ok(L([I(3)])))
}

pub fn list_tail_test() {
  // I think glance fails on this and it shouldn't
  //   "[..[]]"
  //   |> exec()
  //   |> should.equal(Ok(L([])))

  "[1, ..[]]"
  |> exec()
  |> should.equal(Ok(L([I(1)])))

  "[1, 2,..[3]]"
  |> exec()
  |> should.equal(Ok(L([I(1), I(2), I(3)])))
}

pub fn record_creation_test() {
  "1(1)"
  |> exec()
  |> should.equal(Ok(L([I(1)])))
}

pub fn bin_op_test() {
  "1 + 2"
  |> exec()
  |> should.equal(Ok(I(3)))

  "1.0 +. 2.0"
  |> exec()
  |> should.equal(Ok(F(3.0)))
}
