import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import glexer
import glance
import scintilla/value.{F, I, L, R, S, T}
import scintilla/reason as r
import scintilla/prelude
import scintilla/interpreter/runner
import scintilla/read
import repl/reader
import repl/runner as r_runner
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

// needs to be list to be constant
// const env = dict.new()

pub fn literal_test() {
  "1"
  |> exec(dict.new())
  |> should.equal(Ok(I(1)))

  "2.0"
  |> exec(dict.new())
  |> should.equal(Ok(F(2.0)))

  "\"\""
  |> exec(dict.new())
  |> should.equal(Ok(S("")))

  "\"hello\""
  |> exec(dict.new())
  |> should.equal(Ok(S("hello")))
}

pub fn number_negation_test() {
  "-1"
  |> exec(dict.new())
  |> should.equal(Ok(I(-1)))

  "-{1 + 1}"
  |> exec(dict.new())
  |> should.equal(Ok(I(-2)))

  "-1.0"
  |> exec(dict.new())
  |> should.equal(Ok(F(-1.0)))
}

pub fn number_negation_fail_test() {
  "-\"a\""
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.IncorrectTerm("Integer", S("a")))
}

pub fn bool_negation_test() {
  "!True"
  |> exec(prelude.scope())
  |> should.equal(Ok(R("False", [])))

  "!{ True }"
  |> exec(prelude.scope())
  |> should.equal(Ok(R("False", [])))

  "!3"
  |> exec(prelude.scope())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.IncorrectTerm("Boolean", I(3)))
}

pub fn panic_test() {
  "panic"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.Panic(None))

  "panic as \"bad\""
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.Panic(Some("bad")))
  // TODO
  // "panic as { \"very \" <> \"bad\" }"
  // |> exec(dict.new())
  // |> should.equal(Error(r.Panic(Some("bad"))))
  // TODO
  // "panic as x"
  // |> exec(dict.new())
  // |> should.equal(Ok(I(5)))
}

pub fn todo_test() {
  // has message
  "todo(\"bad\")"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.Todo(Some("bad")))

  // evals message
  "todo(\"very\" <> \"bad\")"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.Todo(None))

  // requires string message
  "todo(3)"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.Todo(None))
}

pub fn block_test() {
  "{ 5 }"
  |> exec(dict.new())
  |> should.equal(Ok(I(5)))

  "3 + { 5 }"
  |> exec(dict.new())
  |> should.equal(Ok(I(8)))

  "3 * { 5 + 1 }"
  |> exec(dict.new())
  |> should.equal(Ok(I(18)))

  "{ 5
   \"hey\" }"
  |> exec(dict.new())
  |> should.equal(Ok(S("hey")))

  "{ 1 + 1
   7}"
  |> exec(dict.new())
  |> should.equal(Ok(I(7)))

  "{ 7
   1 + 1}"
  |> exec(dict.new())
  |> should.equal(Ok(I(2)))
}

pub fn tuple_test() {
  "#()"
  |> exec(dict.new())
  |> should.equal(Ok(T([])))

  "#(1, 2.0)"
  |> exec(dict.new())
  |> should.equal(Ok(T([I(1), F(2.0)])))

  "#(1 + 2)"
  |> exec(dict.new())
  |> should.equal(Ok(T([I(3)])))
}

pub fn tuple_index_test() {
  "#(1).0"
  |> exec(dict.new())
  |> should.equal(Ok(I(1)))

  "#(1, 2.0).1"
  |> exec(dict.new())
  |> should.equal(Ok(F(2.0)))
}

pub fn tuple_index_error_test() {
  "\"a\".0"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.IncorrectTerm("Tuple", S("a")))

  "#().2"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.OutOfRange(0, 2))
}

pub fn list_test() {
  "[]"
  |> exec(dict.new())
  |> should.equal(Ok(L([])))

  "[1, 2.0]"
  |> exec(dict.new())
  |> should.equal(Ok(L([I(1), F(2.0)])))

  "[1 + 2]"
  |> exec(dict.new())
  |> should.equal(Ok(L([I(3)])))
}

pub fn list_tail_test() {
  // I think glance fails on this and it shouldn't
  //   "[..[]]"
  //   |> exec(dict.new())
  //   |> should.equal(Ok(L([])))

  "[1, ..[]]"
  |> exec(dict.new())
  |> should.equal(Ok(L([I(1)])))

  "[1, 2,..[3]]"
  |> exec(dict.new())
  |> should.equal(Ok(L([I(1), I(2), I(3)])))
}

pub fn improper_list_test() {
  "[1,..2]"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.IncorrectTerm("List", I(2)))
}

pub fn prelude_creation_test() {
  "Nil"
  |> exec(prelude.scope())
  |> should.equal(Ok(R("Nil", [])))

  "True"
  |> exec(prelude.scope())
  |> should.equal(Ok(R("True", [])))

  "False"
  |> exec(prelude.scope())
  |> should.equal(Ok(R("False", [])))

  "Ok(5)"
  |> exec(prelude.scope())
  |> should.equal(Ok(R("Ok", [glance.Field(None, I(5))])))

  "Error( 3 - 1)"
  |> exec(prelude.scope())
  |> should.equal(Ok(R("Error", [glance.Field(None, I(2))])))
}

pub fn case_test() {
  "case 2 < 1 {
    True -> \"yes\"
    False -> \"no\"
  }"
  |> exec(prelude.scope())
  |> should.equal(Ok(S("no")))

  "case 1 < 2 {
    True -> \"yes\"
    False -> \"no\"
  }"
  |> exec(prelude.scope())
  |> should.equal(Ok(S("yes")))

  "case Nil {
    True -> \"yes\"
    False -> \"no\"
  }"
  |> exec(prelude.scope())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.NoMatch([R("Nil", [])]))

  "case 23 {
    True -> \"yes\"
    False -> \"no\"
  }"
  |> exec(prelude.scope())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.NoMatch([I(23)]))
}

pub fn case_binding_test() {
  "case Ok(2) {
    Ok(x) -> x
  }"
  |> exec(prelude.scope())
  |> should.equal(Ok(I(2)))
}

pub fn case_multiple_binding_test() {
  "case 1, 2 {
    x, y -> #(x, y)
  }"
  |> exec(dict.new())
  |> should.equal(Ok(T([I(1), I(2)])))
}

pub fn incorrect_arity_case_test() {
  "case 1, 2 {
    _ -> \"match\"
  }"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.NoMatch([I(1), I(2)]))
}

pub fn multiple_patterns_test() {
  "case 1, 2 {
    3, y | 1, y -> y
  }"
  |> exec(dict.new())
  |> should.equal(Ok(I(2)))

  "case Error(5) {
  Ok(x) | Error(x) -> x
  }"
  |> exec(prelude.scope())
  |> should.equal(Ok(I(5)))
}

pub fn function_test() {
  // TODO glance should error Empty fn would get formatted as having a todo
  // "fn() { }"
  // |> exec(dict.new())
  // |> should.equal(Ok(Closure([], [], dict.from_list([]))))

  "fn() { 5 }()"
  |> exec(dict.new())
  |> should.equal(Ok(I(5)))

  "fn(x) { x + 1 }(10)"
  |> exec(dict.new())
  |> should.equal(Ok(I(11)))

  "fn(x, y) { x + y }(10, 5)"
  |> exec(dict.new())
  |> should.equal(Ok(I(15)))

  "fn(x, y) {
    x + y
    1
  }(10, 5)"
  |> exec(dict.new())
  |> should.equal(Ok(I(1)))

  "fn(_) { 5 }(2)"
  |> exec(dict.new())
  |> should.equal(Ok(I(5)))
}

pub fn function_error_test() {
  "1()"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.NotAFunction(I(1)))

  "fn(){ 5 }(1, 2)"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.IncorrectArity(0, 2))

  "fn(x){ 5 }(b: 1)"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.MissingField("b"))
}

pub fn top_function_test() {
  let state = #(dict.new(), dict.new())
  let line = "fn foo(a x, b y) { x - y }"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Ok(#(_, initial)) = r_runner.read(term, state)

  let line = "foo(7, 6)"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Ok(#(Some(value), _)) = r_runner.read(term, initial)
  value
  |> should.equal(I(1))

  let line = "foo(b: 3, a: 2)"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Ok(#(Some(value), _)) = r_runner.read(term, initial)
  value
  |> should.equal(I(-1))

  let line = "foo(4, b: 8)"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Ok(#(Some(value), _)) = r_runner.read(term, initial)
  value
  |> should.equal(I(-4))

  let line = "foo(4, c: 8)"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Error(reason) = r_runner.read(term, initial)
  reason
  |> should.equal(r.MissingField("c"))

  let line = "foo(4)"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Error(reason) = r_runner.read(term, initial)
  reason
  |> should.equal(r.IncorrectArity(2, 1))

  let line = "foo(4, 3, 2)"
  let assert Ok(#(term, [])) = reader.parse(line)
  let assert Error(reason) = r_runner.read(term, initial)
  reason
  |> should.equal(r.IncorrectArity(2, 3))
}

pub fn function_capture_test() {
  "let x = fn(x, y, z) { x - y * 2 }
  x(_,3,2)(1)"
  |> exec(dict.new())
  |> should.equal(Ok(I(-5)))

  "let x = fn(x, y, z) { x - y * 2 }
  x(4,_,5)(10)"
  |> exec(dict.new())
  |> should.equal(Ok(I(-16)))

  "let x = fn(x, y, z) { x - y * 2 }
  x(6,7,_)(2)"
  |> exec(dict.new())
  |> should.equal(Ok(I(-8)))
}

// TODO rename bitarray
// Do not support for now
// pub fn bit_string_test() {
//   "<<>>"
//   |> exec(dict.new())
//   |> should.equal(Ok(I(-8)))
// }

pub fn bin_op_test() {
  "1 + 2"
  |> exec(dict.new())
  |> should.equal(Ok(I(3)))

  "1.0 +. 2.0"
  |> exec(dict.new())
  |> should.equal(Ok(F(3.0)))
}

pub fn bin_op_fail_test() {
  "1 + #()"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.IncorrectTerm("Integer", T([])))
}

pub fn pipe_test() -> Nil {
  "let a = fn(x) { x }
  3 |> a"
  |> exec(dict.new())
  |> should.equal(Ok(I(3)))

  "let a = fn(x) { x }
  3 |> a()"
  |> exec(dict.new())
  |> should.equal(Ok(I(3)))
}

pub fn pipe_to_capture_test() -> Nil {
  "let a = fn(x, y) { x - y }
  3 |> a(_, 1)"
  |> exec(dict.new())
  |> should.equal(Ok(I(2)))

  "let a = fn(x, y) { x - y }
  3 |> a(1, _)"
  |> exec(dict.new())
  |> should.equal(Ok(I(-2)))
}

pub fn let_assignment_test() {
  "let x = 1
  x"
  |> exec(dict.new())
  |> should.equal(Ok(I(1)))

  "let x = 1
  let y = 2
  x + y"
  |> exec(dict.new())
  |> should.equal(Ok(I(3)))

  "let x = 1
  let x = 2
  x"
  |> exec(dict.new())
  |> should.equal(Ok(I(2)))
}

pub fn assertion_test() {
  "let assert 1 = 1
  2"
  |> exec(dict.new())
  |> should.equal(Ok(I(2)))

  "let assert 2 = 1"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.FailedAssignment(glance.PatternInt("2"), I(1)))
}

pub fn undefined_variable_test() {
  "x"
  |> exec(dict.new())
  |> should.be_error()
  |> take_reason()
  |> should.equal(r.UndefinedVariable("x"))
}

pub fn finish_on_assignment_test() {
  let assert Error(#(r.Finished(env), _, _)) =
    "let x = 5"
    |> exec(dict.new())
  dict.get(env, "x")
  |> should.equal(Ok(I(5)))
}

// todo assert assignment

pub fn use_test() {
  // "use <- a()
  // 3"
  // needs to be a function that calls x
  // |> exec_with([#("a", r_runner.Builtin(r_runner.Arity1(Ok)))])
  // |> should.equal(Error(r.Finished(dict.from_list([#("x", I(5))]))))

  // only callback
  "use <- fn(f){ f() }
  3"
  |> exec(dict.new())
  |> should.equal(Ok(I(3)))

  "use <- fn(f){ f() }()
  3"
  |> exec(dict.new())
  |> should.equal(Ok(I(3)))

  // extra args
  "use <- fn(a, f){ a + f() }(2)
  3"
  |> exec(dict.new())
  |> should.equal(Ok(I(5)))

  "use a, b <- fn(f){ f(1, 2) }
  #(a, b)"
  |> exec(dict.new())
  |> should.equal(Ok(T([I(1), I(2)])))
}
