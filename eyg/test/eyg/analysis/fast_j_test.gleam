import gleam/io
import gleam/list
import gleam/result
import eyg/parse/lexer
import eyg/parse/parser
import gleeunit/should
import eyg/analysis/fast_j as j
import eyg/analysis/fast_j/debug

fn parse(src) {
  src
  |> lexer.lex()
  |> parser.parse()
  |> should.be_ok()
}

fn do_resolve(return: #(List(#(_, _, _, _)), _)) {
  let #(acc, bindings) = return
  list.map(acc, fn(node) {
    let #(error, typed, effect, env) = node
    let typed = j.resolve(typed, bindings)
    let effect = j.resolve(effect, bindings)
    #(error, typed, effect, env)
  })
}

fn drop_env(results) {
  list.map(results, fn(r) {
    let #(error, type_, eff, _env) = r
    #(error, type_, eff)
  })
}

fn do_render(results) {
  list.map(results, fn(r) {
    let #(error, type_, eff) = r
    #(error, debug.render_type(type_), debug.render_effects(eff))
  })
}

fn calc(source, eff) {
  source
  |> parse
  |> j.infer(eff, j.new_state())
  |> do_resolve()
  |> drop_env()
  |> do_render()
}

fn do_calc(source, eff, state) {
  source
  |> parse
  |> j.infer(eff, state)
  |> do_resolve()
  |> drop_env()
  |> do_render()
}

fn ok(type_, eff) {
  #(Ok(Nil), type_, eff)
}

pub fn variable_test() {
  "x"
  |> calc(j.Empty)
  |> should.equal([#(Error(j.MissingVariable("x")), "0", "<>")])
}

pub fn literal_test() {
  "5"
  |> calc(j.Empty)
  |> should.equal([ok("Integer", "<>")])

  "\"hello\""
  |> calc(j.Empty)
  |> should.equal([ok("String", "<>")])
  // TODO binary needs parsing
}

pub fn function_test() {
  "(_) -> { 5 }"
  |> calc(j.Empty)
  |> should.equal([ok("(0) -> <> Integer", "<>"), ok("Integer", "<>")])

  "(x) -> { x }(5)"
  |> calc(j.Empty)
  |> should.equal([
    ok("Integer", "<>"),
    ok("(Integer) -> <> Integer", "<>"),
    ok("Integer", "<>"),
    ok("Integer", "<>"),
  ])

  "(x, _) -> {
    x
  }(1, \"\")"
  |> calc(j.Empty)
  |> should.equal([
    ok("Integer", "<>"),
    ok("(String) -> <> Integer", "<>"),
    ok("(Integer) -> <> (String) -> <> Integer", "<>"),
    ok("(String) -> <> Integer", "<>"),
    ok("Integer", "<>"),
    ok("Integer", "<>"),
    ok("String", "<>"),
  ])

  "(_, z) -> {
    z
  }(1, \"\")"
  |> calc(j.Empty)
  |> should.equal([
    ok("String", "<>"),
    ok("(String) -> <> String", "<>"),
    ok("(Integer) -> <> (String) -> <> String", "<>"),
    ok("(String) -> <> String", "<>"),
    ok("String", "<>"),
    ok("Integer", "<>"),
    ok("String", "<>"),
  ])
}

pub fn let_test() {
  "let x = 5
  let y = \"\"
  x"
  |> calc(j.Empty)
  |> should.equal([
    ok("Integer", "<>"),
    ok("Integer", "<>"),
    ok("Integer", "<>"),
    ok("String", "<>"),
    ok("Integer", "<>"),
  ])

  "let x = 5
  let x = \"\"
  x"
  |> calc(j.Empty)
  |> should.equal([
    ok("String", "<>"),
    ok("Integer", "<>"),
    ok("String", "<>"),
    ok("String", "<>"),
    ok("String", "<>"),
  ])
}

pub fn let_polymorphism_test() {
  "let f = (x) -> { x }
  let y = f(3)
  f(\"hey\")"
  |> calc(j.Empty)
  |> should.equal([
    ok("String", "<>"),
    ok("(0) -> <> 0", "<>"),
    ok("0", "<>"),
    ok("String", "<>"),
    ok("Integer", "<>"),
    ok("(Integer) -> <> Integer", "<>"),
    ok("Integer", "<>"),
    ok("String", "<>"),
    ok("(String) -> <> String", "<>"),
    ok("String", "<>"),
  ])
}

// compound types

pub fn list_test() {
  "[]"
  |> calc(j.Empty)
  |> should.equal([ok("List(0)", "<>")])

  "[3]"
  |> calc(j.Empty)
  |> should.equal([
    ok("List(Integer)", "<>"),
    ok("(List(Integer)) -> <> List(Integer)", "<>"),
    ok("(Integer) -> <> (List(Integer)) -> <> List(Integer)", "<>"),
    ok("Integer", "<>"),
    ok("List(Integer)", "<>"),
  ])
}

pub fn list_polymorphism_test() {
  "let x = 5
  let l = [x]
  l"
  |> calc(j.Empty)
  |> should.equal([
    ok("List(Integer)", "<>"),
    ok("Integer", "<>"),
    ok("List(Integer)", "<>"),
    ok("List(Integer)", "<>"),
    ok("(List(Integer)) -> <> List(Integer)", "<>"),
    ok("(Integer) -> <> (List(Integer)) -> <> List(Integer)", "<>"),
    ok("Integer", "<>"),
    ok("List(Integer)", "<>"),
    ok("List(Integer)", "<>"),
  ])

  "let l = [(x) -> { x }]
  l"
  |> calc(j.Empty)
  |> should.equal([
    ok("List((6) -> <> 6)", "<>"),
    ok("List((1) -> <> 1)", "<>"),
    ok("(List((1) -> <> 1)) -> <> List((1) -> <> 1)", "<>"),
    #(
      Ok(Nil),
      "((1) -> <> 1) -> <> (List((1) -> <> 1)) -> <> List((1) -> <> 1)",
      "<>",
    ),
    ok("(1) -> <> 1", "<>"),
    ok("1", "<>"),
    ok("List((1) -> <> 1)", "<>"),
    ok("List((6) -> <> 6)", "<>"),
  ])
}

pub fn record_test() {
  "{}"
  |> calc(j.Empty)
  |> should.equal([ok("{}", "<>")])

  "{a: 3}"
  |> calc(j.Empty)
  |> should.equal([
    ok("{a: Integer}", "<>"),
    ok("({}) -> <> {a: Integer}", "<>"),
    ok("(Integer) -> <> ({}) -> <> {a: Integer}", "<>"),
    ok("Integer", "<>"),
    ok("{}", "<>"),
  ])
}

pub fn select_test() {
  "{name: 5}.name"
  |> calc(j.Empty)
  |> should.equal([
    ok("Integer", "<>"),
    ok("({name: Integer}) -> <> Integer", "<>"),
    ok("{name: Integer}", "<>"),
    ok("({}) -> <> {name: Integer}", "<>"),
    ok("(Integer) -> <> ({}) -> <> {name: Integer}", "<>"),
    ok("Integer", "<>"),
    ok("{}", "<>"),
  ])

  "x.name"
  |> calc(j.Empty)
  |> should.equal([
    ok("0", "<>"),
    ok("({name: 0, ..1}) -> <> 0", "<>"),
    #(Error(j.MissingVariable("x")), "{name: 0, ..1}", "<>"),
  ])

  "{}.name"
  |> calc(j.Empty)
  |> should.equal([
    #(Error(j.MissingRow("name")), "2", "<>"),
    #(Ok(Nil), "({name: 0, ..1}) -> <> 0", "<>"),
    #(Ok(Nil), "{}", "<>"),
  ])
  // cant have bare .name because white space will join it to previous thing
}

pub fn tag_test() {
  "Ok"
  |> calc(j.Empty)
  |> should.equal([ok("(0) -> <> [Ok: 0 | ..1]", "<>")])

  "Ok(8)"
  |> calc(j.Empty)
  |> should.equal([
    ok("[Ok: Integer | ..1]", "<>"),
    ok("(Integer) -> <> [Ok: Integer | ..1]", "<>"),
    ok("Integer", "<>"),
  ])
}

pub fn builtin_test() {
  "!integer_add"
  |> calc(j.Empty)
  |> should.equal([ok("(Integer) -> <> (Integer) -> <> Integer", "<>")])

  "!integer_add(1, 2)"
  |> calc(j.Empty)
  |> should.equal([
    ok("Integer", "<>"),
    ok("(Integer) -> <> Integer", "<>"),
    ok("(Integer) -> <> (Integer) -> <> Integer", "<>"),
    ok("Integer", "<>"),
    ok("Integer", "<>"),
  ])

  "!not_a_thing"
  |> calc(j.Empty)
  |> should.equal([#(Error(j.MissingVariable("not_a_thing")), "0", "<>")])
}

pub fn perform_test() {
  "perform Log(\"thing\")"
  |> calc(j.Var(-1))
  |> should.equal([
    #(Ok(Nil), "5", "<Log(String, 5)>"),
    #(Ok(Nil), "(String) -> <Log(String, 5)> 5", "<>"),
    #(Ok(Nil), "String", "<>"),
  ])
}

pub fn perform_unifys_with_env_test() {
  "perform Log(5)"
  |> calc(j.EffectExtend("Log", #(j.String, j.Record(j.Empty)), j.Empty))
  |> should.equal([
    #(Error(j.TypeMismatch(j.String, j.Integer)), "3", "<Log(0, 2)>"),
    #(Ok(Nil), "(0) -> <Log(0, 2)> 2", "<>"),
    #(Ok(Nil), "Integer", "<>"),
  ])
}

pub fn combine_effect_test() {
  "(_) -> {
    let x = perform Log(\"info\")
    perform Foo(5)
  }"
  |> calc(j.Var(-1))
  |> should.equal([
    #(Ok(Nil), "(0) -> <Log(String, 11), Foo(Integer, 8)> 8", "<>"),
    #(Ok(Nil), "8", "<>"),
    #(Ok(Nil), "11", "<Log(String, 11)>"),
    #(Ok(Nil), "(String) -> <Log(String, 11)> 11", "<>"),
    #(Ok(Nil), "String", "<>"),
    #(Ok(Nil), "8", "<Foo(Integer, 8)>"),
    #(Ok(Nil), "(Integer) -> <Foo(Integer, 8)> 8", "<>"),
    #(Ok(Nil), "Integer", "<>"),
  ])

  "(_) -> {
    perform Foo(perform Log(\"info\"))
  }"
  |> calc(j.Var(-1))
  |> should.equal([
    #(Ok(Nil), "(0) -> <Log(String, 11), Foo(11, 4)> 4", "<>"),
    #(Ok(Nil), "4", "<Foo(11, 4)>"),
    #(Ok(Nil), "(11) -> <Foo(11, 4)> 4", "<>"),
    #(Ok(Nil), "11", "<Log(String, 11)>"),
    #(Ok(Nil), "(String) -> <Log(String, 11)> 11", "<>"),
    #(Ok(Nil), "String", "<>"),
  ])
}

pub fn combine_unknown_effect_test() {
  "(f) -> {
    let x = f(\"info\")
    perform Foo(5)
  }"
  |> calc(j.Var(-1))
  |> should.equal([
    ok(
      "((String) -> <Foo(Integer, 5), ..4> 2) -> <Foo(Integer, 5), ..4> 5",
      "<>",
    ),
    #(Ok(Nil), "5", "<>"),
    #(Ok(Nil), "2", "<Foo(Integer, 5), ..4>"),
    #(Ok(Nil), "(String) -> <Foo(Integer, 5), ..4> 2", "<>"),
    #(Ok(Nil), "String", "<>"),
    #(Ok(Nil), "5", "<Foo(Integer, 5)>"),
    #(Ok(Nil), "(Integer) -> <Foo(Integer, 5)> 5", "<>"),
    #(Ok(Nil), "Integer", "<>"),
  ])

  "(f) -> {
    f(perform Log(\"info\"))
  }"
  |> calc(j.Var(-1))
  |> should.equal([
    #(
      Ok(Nil),
      "((4) -> <Log(String, 4), ..3> 6) -> <Log(String, 4), ..3> 6",
      "<>",
    ),
    #(Ok(Nil), "6", "<Log(String, 4), ..3>"),
    #(Ok(Nil), "(4) -> <Log(String, 4), ..3> 6", "<>"),
    #(Ok(Nil), "4", "<Log(String, 4)>"),
    #(Ok(Nil), "(String) -> <Log(String, 4)> 4", "<>"),
    #(Ok(Nil), "String", "<>"),
  ])
}

pub fn first_class_function_with_effects_test() {
  let state = j.new_state()
  let #(state, var) = j.newvar(state)
  "(f) -> {
    f({})
  }"
  |> do_calc(var, state)
  |> should.equal([
    #(Ok(Nil), "(({}) -> <..2> 3) -> <..2> 3", "<>"),
    #(Ok(Nil), "3", "<..2>"),
    #(Ok(Nil), "({}) -> <..2> 3", "<>"),
    #(Ok(Nil), "{}", "<>"),
  ])
}

// This needs occurs
pub fn poly_in_effect_test() {
  "(_) -> {
    let do = (f) -> { f(1) }
    let _ = do((x) -> {  perform Bar(5)  })
    do((x) -> { perform Foo(5) })
  }"
  |> calc(j.Empty)
  |> should.equal([
    #(Ok(Nil), "(0) -> <> 15", "<>"),
    #(Ok(Nil), "15", "<>"),
    #(Ok(Nil), "((Integer) -> <..3> 4) -> <..3> 4", "<>"),
    #(Ok(Nil), "4", "<..3>"),
    #(Ok(Nil), "(Integer) -> <..3> 4", "<>"),
    #(Ok(Nil), "Integer", "<>"),
    #(Ok(Nil), "15", "<>"),
    #(Ok(Nil), "6", "<Bar(Integer, 6), ..10>"),
    #(
      Ok(Nil),
      "((Integer) -> <Bar(Integer, 6), ..10> 6) -> <Bar(Integer, 6), ..10> 6",
      "<>",
    ),
    #(Ok(Nil), "(Integer) -> <Bar(Integer, 6)> 6", "<>"),
    #(Ok(Nil), "6", "<Bar(Integer, 6)>"),
    #(Ok(Nil), "(Integer) -> <Bar(Integer, 6)> 6", "<>"),
    #(Ok(Nil), "Integer", "<>"),
    #(Ok(Nil), "15", "<Foo(Integer, 15), ..19>"),
    #(
      Ok(Nil),
      "((Integer) -> <Foo(Integer, 15), ..19> 15) -> <Foo(Integer, 15), ..19> 15",
      "<>",
    ),
    #(Ok(Nil), "(Integer) -> <Foo(Integer, 15)> 15", "<>"),
    #(Ok(Nil), "15", "<Foo(Integer, 15)>"),
    #(Ok(Nil), "(Integer) -> <Foo(Integer, 15)> 15", "<>"),
    #(Ok(Nil), "Integer", "<>"),
  ])
  todo as "shouldn error"
}
// This is worth having because polymorphism doesn't happen for parameter fn
// pub fn poly_in_effect_unification_test() {
//   "(f) ->
//     let _ = f(1)
//     perform Log(\"\")"
//   |> parse
//   |> j.infer
//   |> do_resolve()
//   |> drop_env()
//   |> do_render()
//   |> should.equal([
//     ok("((Integer) -> <Log(String, 4)> 1) -> <Log(String, 4)> 4", "<>"),
//     ok("4", "<>"),
//     ok("1", "<Log(String, 4)>"),
//     ok("(Integer) -> <Log(String, 4)> 1", "<>"),
//     ok("Integer", "<>"),
//     ok("4", "<Log(String, 4)>"),
//     ok("(String) -> <Log(String, 4)> 4", "<>"),
//     ok("String", "<>"),
//   ])
// }
// let with two performs has a closed total effect
// f(5) Has total effect something that might depend on f

// Test if a sometihng accepting functions is passed in something pure

// let x = perform A({})
// perform B({})

// Using unhandled effects at the top for anything i.e. prompt breaks the idea of compiling in native effects

// function(_) {
//   perform A({}, j1)
// }
//
// function j1(x) {
//   perform B({})
// }
//
// pub fn simple_fn_test() {
//   "(x) -> x"
//   todo
// }

// pub fn assignment_test() {
//   "let f = (x) -> x
//   f(5)"
//   |> parse()
//   |> fast_j.infer()
// }
// pub fn assignment_test() {
//   "(f) ->
//     let x = f(5)
//     x
//   "
//   |> parse()
//   todo
// }
