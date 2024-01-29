import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import glexer
import glance
import scintilla/value as v
import scintilla/reason as r
import scintilla/prelude
import scintilla/interpreter/runner
import scintilla/read
import gleeunit/should

fn exec(src, env) {
  glexer.new(src)
  |> glexer.lex()
  |> list.filter(fn(pair) { !glance.is_whitespace(pair.0) })
  |> read.statements()
  |> should.be_ok()
  |> runner.exec(env)
}

fn take_reason(err: #(_, _, _)) {
  err.0
}

pub fn discard_pattern_test() {
  "let _ = 1"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.new()))

  "let _x = 1"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.new()))
}

pub fn int_pattern_test() {
  "let 1 = 1"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.new()))

  "let 1 = 2"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.FailedAssignment(glance.PatternInt("1"), v.I(2)))

  "let 1 = #()"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.IncorrectTerm("Int", v.T([])))
}

pub fn float_pattern_test() {
  "let 1.0 = 1.0"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.new()))

  "let 1.0 = 2.0"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.FailedAssignment(glance.PatternFloat("1.0"), v.F(2.0)))

  "let 1.0 = #()"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.IncorrectTerm("Float", v.T([])))
}

pub fn string_pattern_test() {
  "let \"hey\" = \"hey\""
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.new()))

  "let \"hey\" = \"hello\""
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.FailedAssignment(glance.PatternString("hey"), v.S("hello")))

  "let \"hey\" = #()"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.IncorrectTerm("String", v.T([])))
}

pub fn string_concat_pattern_test() {
  "let \"he\" <> _ = \"hey\""
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.new()))

  "let \"he\" <> x = \"hey\""
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.from_list([#("x", v.S("y"))])))

  "let \"!\" <> x = \"hello\""
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.FailedAssignment(
    glance.PatternConcatenate("!", glance.Named("x")),
    v.S("hello"),
  ))

  "let \"he\" <> _ = #()"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.IncorrectTerm("String", v.T([])))
}

pub fn tuple_pattern_test() {
  "let #() = #()"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.new()))

  "let #(1, 2) = #(1, 2)"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.new()))

  "let #() = #(2)"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.FailedAssignment(glance.PatternTuple([]), v.T([v.I(2)])))

  "let #() = \"hey\""
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.IncorrectTerm("Tuple", v.S("hey")))
}

pub fn list_pattern_test() {
  "let [] = []"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.new()))

  "let [1, 2] = [1, 2]"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.new()))

  "let [] = [2]"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.FailedAssignment(
    glance.PatternList([], None),
    v.L([v.I(2)]),
  ))

  "let [] = \"hey\""
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.IncorrectTerm("List", v.S("hey")))
}

pub fn list_spread_pattern_test() {
  "let [a,..b] = [1]"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.from_list([#("a", v.I(1)), #("b", v.L([]))])))

  "let [a,..b] = [1, 2]"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(
    r.Finished(dict.from_list([#("a", v.I(1)), #("b", v.L([v.I(2)]))])),
  )
}

pub fn enum_match_test() {
  "let True = True"
  |> exec(prelude.scope())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(prelude.scope()))

  // let assert Error(r.FailedAssignment(_, _)) =
  "let True = False"
  |> exec(prelude.scope())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.FailedAssignment(
    glance.PatternConstructor(None, "True", [], False),
    v.false,
  ))

  "let True = \"hey\""
  |> exec(prelude.scope())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.IncorrectTerm("Custom Type", v.S("hey")))
}

pub fn record_match_test() {
  let assert r.Finished(_env) =
    "let Ok(1) = Ok(1)"
    |> exec(prelude.scope())
    |> should.be_error()
    |> take_reason()

  let assert r.Finished(env) =
    "let Ok(x) = Ok(1)"
    |> exec(prelude.scope())
    |> should.be_error()
    |> take_reason()

  dict.get(env, "x")
  |> should.equal(Ok(v.I(1)))

  let assert r.IncorrectArity(0, 1) =
    "let Ok() = Ok(2)"
    |> exec(prelude.scope())
    |> should.be_error()
    |> take_reason()

  let assert r.FailedAssignment(_, _) =
    "let Ok(1) = Ok(2)"
    |> exec(prelude.scope())
    |> should.be_error()
    |> take_reason()

  let assert r.IncorrectTerm("Custom Type", _) =
    "let Ok(_) = \"hey\""
    |> exec(prelude.scope())
    |> should.be_error()
    |> take_reason()
}

// TODO named args in record and spread

pub fn assignment_test() {
  "let [1 as a,..[] as b] = [1]"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason
  |> should.equal(r.Finished(dict.from_list([#("a", v.I(1)), #("b", v.L([]))])))
}
