import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import eyg/parse
import gleam/dict
import gleam/list
import gleeunit/should

fn parse(src) {
  src
  |> parse.all_from_string()
  |> should.be_ok()
}

fn do_resolve(return) {
  let #(acc, bindings) = return
  let acc = ir.get_annotation(acc)
  let #(_, acc) =
    list.map_fold(acc, bindings, fn(bindings, node) {
      let #(error, typed, effect, env) = node
      // let #(s, typed) = j.instantiate(scheme, s)
      // TODO do I need state
      let typed = binding.resolve(typed, bindings)
      // let #(s, effect) = j.instantiate(effect, s)

      let effect = binding.resolve(effect, bindings)
      #(bindings, #(error, typed, effect, env))
    })
  acc
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
    #(error, debug.mono(type_), debug.effect(eff))
  })
}

fn calc(source, eff) {
  source
  |> parse
  |> j.infer(eff, dict.new(), 0, j.new_state())
  |> do_resolve()
  |> drop_env()
  |> do_render()
}

fn do_calc(source, eff, state) {
  source
  |> parse
  |> j.infer(eff, dict.new(), 0, state)
  |> do_resolve()
  |> drop_env()
  |> do_render()
}

fn ok(type_, eff) {
  #(Ok(Nil), type_, eff)
}

pub fn variable_test() {
  "x"
  |> calc(t.Empty)
  |> should.equal([#(Error(error.MissingVariable("x")), "0", "")])
}

pub fn literal_test() {
  "5"
  |> calc(t.Empty)
  |> should.equal([ok("Integer", "")])

  "\"hello\""
  |> calc(t.Empty)
  |> should.equal([ok("String", "")])
  // binary needs parsing to test
}

pub fn simple_function_test() {
  "(_) -> { 5 }"
  |> calc(t.Empty)
  |> should.equal([ok("(0) -> Integer", ""), ok("Integer", "")])

  "(x) -> { x }(5)"
  |> calc(t.Empty)
  |> should.equal([
    ok("Integer", ""),
    ok("(Integer) -> Integer", ""),
    ok("Integer", ""),
    ok("Integer", ""),
  ])

  "(x, _) -> {
    x
  }(1, \"\")"
  |> calc(t.Empty)
  |> should.equal([
    ok("Integer", ""),
    ok("(String) -> Integer", ""),
    ok("(Integer, String) -> Integer", ""),
    ok("(String) -> Integer", ""),
    ok("Integer", ""),
    ok("Integer", ""),
    ok("String", ""),
  ])

  "(_, z) -> {
    z
  }(1, \"\")"
  |> calc(t.Empty)
  |> should.equal([
    ok("String", ""),
    ok("(String) -> String", ""),
    ok("(Integer, String) -> String", ""),
    ok("(String) -> String", ""),
    ok("String", ""),
    ok("Integer", ""),
    ok("String", ""),
  ])
}

pub fn let_test() {
  "let x = 5
  let y = \"\"
  x"
  |> calc(t.Empty)
  |> should.equal([
    ok("Integer", ""),
    ok("Integer", ""),
    ok("Integer", ""),
    ok("String", ""),
    ok("Integer", ""),
  ])

  "let x = 5
  let x = \"\"
  x"
  |> calc(t.Empty)
  |> should.equal([
    ok("String", ""),
    ok("Integer", ""),
    ok("String", ""),
    ok("String", ""),
    ok("String", ""),
  ])
}

pub fn let_polymorphism_test() {
  "let f = (x) -> { x }
  let y = f(3)
  f(\"hey\")"
  |> calc(t.Empty)
  |> should.equal([
    ok("String", ""),
    ok("(0) -> 0", ""),
    ok("0", ""),
    ok("String", ""),
    ok("Integer", ""),
    ok("(Integer) -> Integer", ""),
    ok("Integer", ""),
    ok("String", ""),
    ok("(String) -> String", ""),
    ok("String", ""),
  ])
}

// // compound types

pub fn list_test() {
  "[]"
  |> calc(t.Empty)
  |> should.equal([ok("List(0)", "")])

  "[3]"
  |> calc(t.Empty)
  |> should.equal([
    ok("List(Integer)", ""),
    ok("(List(Integer)) -> List(Integer)", ""),
    ok("(Integer, List(Integer)) -> List(Integer)", ""),
    ok("Integer", ""),
    ok("List(Integer)", ""),
  ])
}

pub fn list_polymorphism_test() {
  "let x = 5
  let l = [x]
  l"
  |> calc(t.Empty)
  |> should.equal([
    ok("List(Integer)", ""),
    ok("Integer", ""),
    ok("List(Integer)", ""),
    ok("List(Integer)", ""),
    ok("(List(Integer)) -> List(Integer)", ""),
    ok("(Integer, List(Integer)) -> List(Integer)", ""),
    ok("Integer", ""),
    ok("List(Integer)", ""),
    ok("List(Integer)", ""),
  ])

  "let l = [(x) -> { x }]
  l"
  |> calc(t.Empty)
  |> should.equal([
    #(Ok(Nil), "List((10 <..11>) -> 10)", ""),
    #(Ok(Nil), "List((3 <..4>) -> 3)", ""),
    #(Ok(Nil), "(List((3 <..4>) -> 3)) -> List((3 <..4>) -> 3)", ""),
    #(
      Ok(Nil),
      "((3 <..4>) -> 3, List((3 <..4>) -> 3)) -> List((3 <..4>) -> 3)",
      "",
    ),
    #(Ok(Nil), "(3) -> 3", ""),
    #(Ok(Nil), "3", ""),
    #(Ok(Nil), "List((3 <..4>) -> 3)", ""),
    #(Ok(Nil), "List((10 <..11>) -> 10)", ""),
  ])
}

pub fn record_test() {
  "{}"
  |> calc(t.Empty)
  |> should.equal([ok("{}", "")])

  "{a: 3}"
  |> calc(t.Empty)
  |> should.equal([
    ok("{a: Integer}", ""),
    ok("({}) -> {a: Integer}", ""),
    ok("(Integer, {}) -> {a: Integer}", ""),
    ok("Integer", ""),
    ok("{}", ""),
  ])
}

pub fn record_unification_test() {
  "({a,b}) -> { a }({a: 1, b:\"\"}) "
  |> calc(t.Empty)
  |> should.equal([
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "({a: Integer, b: String}) -> Integer", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "({a: Integer, b: String}) -> Integer", ""),
    #(Ok(Nil), "{a: Integer, b: String}", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "String", ""),
    #(Ok(Nil), "({b: String, a: Integer}) -> String", ""),
    #(Ok(Nil), "{a: Integer, b: String}", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "{a: Integer, b: String}", ""),
    #(Ok(Nil), "({b: String}) -> {a: Integer, b: String}", ""),
    #(Ok(Nil), "(Integer, {b: String}) -> {a: Integer, b: String}", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "{b: String}", ""),
    #(Ok(Nil), "({}) -> {b: String}", ""),
    #(Ok(Nil), "(String, {}) -> {b: String}", ""),
    #(Ok(Nil), "String", ""),
    #(Ok(Nil), "{}", ""),
  ])
}

pub fn select_test() {
  "{name: 5}.name"
  |> calc(t.Empty)
  |> should.equal([
    ok("Integer", ""),
    ok("({name: Integer}) -> Integer", ""),
    ok("{name: Integer}", ""),
    ok("({}) -> {name: Integer}", ""),
    ok("(Integer, {}) -> {name: Integer}", ""),
    ok("Integer", ""),
    ok("{}", ""),
  ])

  "x.name"
  |> calc(t.Empty)
  |> should.equal([
    ok("0", ""),
    ok("({name: 0, ..1}) -> 0", ""),
    #(Error(error.MissingVariable("x")), "{name: 0, ..1}", ""),
  ])

  "{}.name"
  |> calc(t.Empty)
  // You could unify with return type if it exists
  |> should.equal([
    #(Error(error.MissingRow("name")), "3", ""),
    #(Ok(Nil), "({name: 0, ..1}) -> 0", ""),
    #(Ok(Nil), "{}", ""),
  ])
  // cant have bare .name because white space will join it to previous thing
}

pub fn tag_test() {
  "Ok"
  |> calc(t.Empty)
  |> should.equal([ok("(0) -> Ok: 0 | ..1", "")])

  "Ok(8)"
  |> calc(t.Empty)
  |> should.equal([
    ok("Ok: Integer | ..1", ""),
    ok("(Integer) -> Ok: Integer | ..1", ""),
    ok("Integer", ""),
  ])
}

pub fn builtin_test() {
  "!int_add"
  |> calc(t.Empty)
  |> should.equal([ok("(Integer, Integer) -> Integer", "")])

  "!int_add(1, 2)"
  |> calc(t.Empty)
  |> should.equal([
    ok("Integer", ""),
    ok("(Integer) -> Integer", ""),
    ok("(Integer, Integer) -> Integer", ""),
    ok("Integer", ""),
    ok("Integer", ""),
  ])

  let state = j.new_state()
  let #(var, state) = binding.mono(0, state)
  "!int_add(1, 2)"
  |> do_calc(var, state)
  |> should.equal([
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "(Integer) -> Integer", ""),
    #(Ok(Nil), "(Integer, Integer) -> Integer", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "Integer", ""),
  ])

  "!not_a_thing"
  |> calc(t.Empty)
  |> should.equal([#(Error(error.MissingBuiltin("not_a_thing")), "0", "")])
}

// (x) -<Log String {}, Alert String 0, ..1> List(x)
pub fn perform_test() {
  let state = j.new_state()
  let #(var, state) = binding.mono(0, state)
  "perform Log(\"thing\")"
  |> do_calc(var, state)
  |> should.equal([
    #(Ok(Nil), "2", "Log(↑String ↓2)"),
    #(Ok(Nil), "(String <Log(↑String ↓2)>) -> 2", ""),
    #(Ok(Nil), "String", ""),
  ])
}

pub fn perform_unifys_with_env_test() {
  "perform Log(5)"
  |> calc(t.EffectExtend("Log", #(t.String, t.Record(t.Empty)), t.Empty))
  |> should.equal([
    #(Error(error.TypeMismatch(t.Integer, t.String)), "1", "Log(↑Integer ↓1)"),
    #(Ok(Nil), "(Integer <Log(↑Integer ↓1)>) -> 1", ""),
    #(Ok(Nil), "Integer", ""),
  ])
}

pub fn only_unknown_effect_test() {
  "(f) -> {
    f(5)
  }"
  |> calc(t.Empty)
  |> should.equal([
    #(Ok(Nil), "((Integer <..1>) -> 2 <..1>) -> 2", ""),
    #(Ok(Nil), "2", "..1"),
    #(Ok(Nil), "(Integer <..1>) -> 2", ""),
    #(Ok(Nil), "Integer", ""),
  ])
}

pub fn combine_effect_test() {
  "(_) -> {
    let x = perform Log(\"info\")
    perform Foo(5)
  }"
  |> calc(t.Var(-1))
  |> should.equal([
    #(Ok(Nil), "(0 <Log(↑String ↓3), Foo(↑Integer ↓13)>) -> 13", ""),
    #(Ok(Nil), "13", ""),
    #(Ok(Nil), "3", "Log(↑String ↓3)"),
    #(Ok(Nil), "(String <Log(↑String ↓3)>) -> 3", ""),
    #(Ok(Nil), "String", ""),
    #(Ok(Nil), "13", "Foo(↑Integer ↓13)"),
    #(Ok(Nil), "(Integer <Foo(↑Integer ↓13)>) -> 13", ""),
    #(Ok(Nil), "Integer", ""),
  ])

  "(_) -> {
    perform Foo(perform Log(\"info\"))
  }"
  |> calc(t.Var(-1))
  |> should.equal([
    #(Ok(Nil), "(0 <Log(↑String ↓12), Foo(↑12 ↓13)>) -> 13", ""),
    #(Ok(Nil), "13", "Foo(↑12 ↓13)"),
    #(Ok(Nil), "(12 <Foo(↑12 ↓13)>) -> 13", ""),
    #(Ok(Nil), "12", "Log(↑String ↓12)"),
    #(Ok(Nil), "(String <Log(↑String ↓12)>) -> 12", ""),
    #(Ok(Nil), "String", ""),
  ])
}

pub fn combine_with_pure_test() {
  "(_) -> {
    let _ = (x) -> {
      x
    }(5)
    perform Log(\"info\")
  }"
  |> calc(t.Empty)
  |> should.equal([
    #(Ok(Nil), "(0 <Log(↑String ↓7)>) -> 7", ""),
    #(Ok(Nil), "7", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "(Integer) -> Integer", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "7", "Log(↑String ↓7)"),
    #(Ok(Nil), "(String <Log(↑String ↓7)>) -> 7", ""),
    #(Ok(Nil), "String", ""),
  ])
}

pub fn combine_unknown_effect_test() {
  "(f) -> {
    let x = f(\"info\")
    perform Foo(5)
  }"
  |> calc(t.Empty)
  |> should.equal([
    #(
      Ok(Nil),
      "((String <Foo(↑Integer ↓5), ..6>) -> 2 <Foo(↑Integer ↓5), ..6>) -> 5",
      "",
    ),
    #(Ok(Nil), "5", ""),
    #(Ok(Nil), "2", "Foo(↑Integer ↓5), ..6"),
    #(Ok(Nil), "(String <Foo(↑Integer ↓5), ..6>) -> 2", ""),
    #(Ok(Nil), "String", ""),
    #(Ok(Nil), "5", "Foo(↑Integer ↓5)"),
    #(Ok(Nil), "(Integer <Foo(↑Integer ↓5)>) -> 5", ""),
    #(Ok(Nil), "Integer", ""),
  ])

  "(f) -> {
    f(perform Log(\"info\"))
  }"
  |> calc(t.Empty)
  |> should.equal([
    #(
      Ok(Nil),
      "((3 <Log(↑String ↓3), ..4>) -> 7 <Log(↑String ↓3), ..4>) -> 7",
      "",
    ),
    #(Ok(Nil), "7", "Log(↑String ↓3), ..4"),
    #(Ok(Nil), "(3 <Log(↑String ↓3), ..4>) -> 7", ""),
    #(Ok(Nil), "3", "Log(↑String ↓3)"),
    #(Ok(Nil), "(String <Log(↑String ↓3)>) -> 3", ""),
    #(Ok(Nil), "String", ""),
  ])
}

pub fn first_class_function_with_effects_test() {
  let state = j.new_state()
  let #(var, state) = binding.mono(0, state)
  "(f) -> {
    f({})
  }"
  |> do_calc(var, state)
  |> should.equal([
    #(Ok(Nil), "(({} <..2>) -> 3 <..2>) -> 3", ""),
    #(Ok(Nil), "3", "..2"),
    #(Ok(Nil), "({} <..2>) -> 3", ""),
    #(Ok(Nil), "{}", ""),
  ])

  "(f) -> {
    (_) -> {
      f({})
    }
  }"
  |> calc(t.Empty)
  |> should.equal([
    #(Ok(Nil), "(({} <..3>) -> 4, 2 <..3>) -> 4", ""),
    #(Ok(Nil), "(2 <..3>) -> 4", ""),
    #(Ok(Nil), "4", "..3"),
    #(Ok(Nil), "({} <..3>) -> 4", ""),
    #(Ok(Nil), "{}", ""),
  ])
}

// How do I explain in the written word
pub fn unify_fn_arg_test() {
  "(_) -> {
    (f) -> { f(1) }((x) -> { \"\" })
  }"
  |> calc(t.Empty)
  |> should.equal([
    #(Ok(Nil), "(0) -> String", ""),
    #(Ok(Nil), "String", ""),
    #(Ok(Nil), "((Integer <..1>) -> String <..1>) -> String", ""),
    // not sure this effect should be here
    #(Ok(Nil), "String", "..1"),
    #(Ok(Nil), "(Integer <..1>) -> String", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "(Integer) -> String", ""),
    #(Ok(Nil), "String", ""),
  ])
}

pub fn poly_in_effect_test() {
  "(_) -> {
    let do = (f) -> { f(1) }
    let _ = do((x) -> {  perform Bar(5)  })
    do((x) -> { perform Foo(5) })
  }"
  |> calc(t.Empty)
  |> should.equal([
    #(Ok(Nil), "(0 <Bar(↑Integer ↓7), Foo(↑Integer ↓29)>) -> 29", ""),
    #(Ok(Nil), "29", ""),
    #(Ok(Nil), "((Integer <..3>) -> 4 <..3>) -> 4", ""),
    #(Ok(Nil), "4", "..3"),
    #(Ok(Nil), "(Integer <..3>) -> 4", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "29", ""),
    #(Ok(Nil), "7", "Bar(↑Integer ↓7)"),
    #(
      Ok(Nil),
      "((Integer <Bar(↑Integer ↓7), Foo(↑Integer ↓29), ..30>) -> 7 <Bar(↑Integer ↓7), Foo(↑Integer ↓29), ..30>) -> 7",
      "",
    ),
    #(Ok(Nil), "(Integer <Bar(↑Integer ↓7)>) -> 7", ""),
    #(Ok(Nil), "7", "Bar(↑Integer ↓7)"),
    #(Ok(Nil), "(Integer <Bar(↑Integer ↓7)>) -> 7", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "29", "Foo(↑Integer ↓29)"),
    #(
      Ok(Nil),
      "((Integer <Foo(↑Integer ↓29), Bar(↑Integer ↓7), ..30>) -> 29 <Foo(↑Integer ↓29), Bar(↑Integer ↓7), ..30>) -> 29",
      "",
    ),
    #(Ok(Nil), "(Integer <Foo(↑Integer ↓29)>) -> 29", ""),
    #(Ok(Nil), "29", "Foo(↑Integer ↓29)"),
    #(Ok(Nil), "(Integer <Foo(↑Integer ↓29)>) -> 29", ""),
    #(Ok(Nil), "Integer", ""),
  ])
}
