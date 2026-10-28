import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/list
import gleeunit/should
import simplifile

pub fn captured_record_field_is_not_generalised_test() {
  let source =
    "(r) -> {
      let _ = r.a
      let same = (s) -> {
        let _ = s.b
        !equal(r, s)
      }
      let _ = same({a: 1, b: 1})
      same({a: 1, b: \"\"})
    }"
  let assert j.Done(analysis) = j.check(j.pure(), parse(source))
  j.all_errors(analysis)
  |> list.map(fn(entry) { entry.1 })
  |> should.equal([error.TypeMismatch(t.String, t.Integer)])
}

pub fn effect_reply_is_not_generalised_test() {
  "(_) -> {
    let _ = perform Other({})
    let x = perform Ping({})
    let _ = !int_add(x, 1)
    !equal(x, \"\")
  }"
  |> calc(t.Empty)
  |> should.equal([
    ok("(0 <Other(↑{} ↓3), Ping(↑{} ↓Integer)>) -> 26", ""),
    ok("26", ""),
    ok("3", "Other(↑{} ↓3)"),
    ok("({} <Other(↑{} ↓3)>) -> 3", ""),
    ok("{}", ""),
    ok("26", ""),
    ok("Integer", "Ping(↑{} ↓Integer)"),
    ok("({} <Ping(↑{} ↓Integer)>) -> Integer", ""),
    ok("{}", ""),
    ok("26", ""),
    ok("Integer", ""),
    ok("(Integer) -> Integer", ""),
    ok("(Integer, Integer) -> Integer", ""),
    ok("Integer", ""),
    ok("Integer", ""),
    #(Error(error.TypeMismatch(t.String, t.Integer)), "26", ""),
    ok("(Integer) -> [True: {} | False: {}]", ""),
    ok("(Integer, Integer) -> [True: {} | False: {}]", ""),
    ok("Integer", ""),
    ok("String", ""),
  ])
}

fn parse(src) {
  src
  |> parser.all_from_string()
  |> should.be_ok()
}

fn do_resolve(analysis: j.Analysis(_)) {
  let acc = analysis.tree
  let bindings = analysis.bindings
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
  let context = j.Context(..j.pure(), eff:)
  source
  |> parse
  |> j.check_with_references(context, dict.new(), _)
  |> do_resolve()
  |> drop_env()
  |> do_render()
}

fn do_calc(source, eff, bindings) {
  let context = j.Context(..j.pure(), eff:, bindings:)
  source
  |> parse
  |> j.check_with_references(context, dict.new(), _)
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

pub fn expectation_constrains_the_result_test() {
  let context = j.pure() |> j.with_expected_type(t.String)
  let assert j.Done(analysis) = j.check(context, parse("5"))
  assert j.all_errors(analysis)
    == [
      #(analysis.original.1, error.TypeMismatch(t.Integer, t.String)),
    ]
}

pub fn info_at_resolves_type_and_effect_test() {
  let effect = t.EffectExtend("Log", #(t.String, t.Integer), t.Empty)
  let context = j.pure() |> j.with_effect("Log", t.String, t.Integer)
  let source = parse("perform Log(\"hello\")")
  let assert j.Done(analysis) = j.check(context, source)

  assert j.info_at(analysis, source.1)
    == Ok(j.NodeInfo(Ok(Nil), t.Integer, effect, []))
  assert j.type_at(analysis, source.1) == Ok(t.Integer)
}

pub fn info_at_preserves_scope_test() {
  let source = #(
    ir.Let("x", #(ir.Integer(5), "value"), #(ir.Variable("x"), "body")),
    "root",
  )
  let assert j.Done(analysis) = j.check(j.pure(), source)

  assert j.info_at(analysis, "body")
    == Ok(j.NodeInfo(Ok(Nil), t.Integer, t.Empty, [#("x", t.Integer)]))
  assert j.scope_at(analysis, "body") == Ok([#("x", t.Integer)])
  assert j.info_at(analysis, "absent") == Error(Nil)
}

pub fn failed_expectation_retains_bindings_and_resolves_errors_test() {
  let #(arg, bindings) = binding.mono(1, dict.new())
  let context =
    j.Context(..j.pure(), bindings:)
    |> j.with_expected_type(t.Fun(arg, t.Empty, t.List(arg)))
  let source = parse("(x) -> { !string_uppercase(x) }")
  let assert j.Done(analysis) = j.check(context, source)
  let reason = error.TypeMismatch(t.String, t.List(t.String))

  assert binding.resolve(arg, analysis.bindings) == t.String
  assert j.info_at(analysis, source.1)
    == Ok(
      j.NodeInfo(Error(reason), t.Fun(t.String, t.Empty, t.String), t.Empty, []),
    )
  assert j.all_errors(analysis) == [#(source.1, reason)]
}

pub fn failed_application_retains_partial_constraints_test() {
  let source = parse("(f) -> { !int_add(f(1), 1) }((x) -> { \"hello\" })")
  let assert #(ir.Apply(_, argument), _) = source
  let assert j.Done(analysis) = j.check(j.pure(), source)

  assert j.type_at(analysis, argument.1)
    == Ok(t.Fun(t.Integer, t.Empty, t.String))
  assert j.all_errors(analysis)
    == [#(source.1, error.TypeMismatch(t.String, t.Integer))]
}

pub fn failed_effect_check_retains_partial_constraints_test() {
  let #(field, bindings) = binding.mono(1, dict.new())
  let lift = t.record([#("x", field), #("y", t.Integer)])
  let context =
    j.Context(..j.pure(), bindings:)
    |> j.with_effect("Ping", lift, t.unit)
  let source = parse("perform Ping({x: 1, y: \"bad\"})")
  let assert j.Done(analysis) = j.check(context, source)

  assert binding.resolve(field, analysis.bindings) == t.Integer
  assert j.all_errors(analysis)
    == [#(source.1, error.TypeMismatch(t.String, t.Integer))]
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

pub fn top_level_polymorphic_function_test() {
  let assert j.Done(identity) =
    j.check(j.pure(), ir.lambda("x", ir.variable("x")))
  assert t.Fun(t.Var(#(True, 0)), t.Empty, t.Var(#(True, 0)))
    == j.poly_type(identity)
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
  |> should.equal([ok("(0) -> [Ok: 0 | ..1]", "")])

  "Ok(8)"
  |> calc(t.Empty)
  |> should.equal([
    ok("[Ok: Integer | ..1]", ""),
    ok("(Integer) -> [Ok: Integer | ..1]", ""),
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

  let state = dict.new()
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

  "match !string_split_once(\"a:b\", \":\") {
    Ok(parts) -> { parts.pre }
    Error(_) -> { \"\" }
  }"
  |> calc(t.Empty)
  |> list.first
  |> should.equal(Ok(ok("String", "")))

  "!not_a_thing"
  |> calc(t.Empty)
  |> should.equal([#(Error(error.MissingBuiltin("not_a_thing")), "0", "")])
}

pub fn fix_test() {
  "!fix"
  |> calc(t.Empty)
  |> should.equal([
    ok("(((0 <..1>) -> 2, 0 <..1>) -> 2, 0 <..1>) -> 2", ""),
  ])

  "!fix((self, x) -> { !int_add(x, 1) })"
  |> calc(t.Empty)
  |> list.first
  |> should.equal(Ok(ok("(Integer) -> Integer", "")))
}

pub fn fix_of_non_function_test() {
  "!fix((x) -> { !int_add(x, 1) })"
  |> calc(t.Empty)
  |> list.first
  |> should.equal(
    Ok(#(
      Error(error.TypeMismatch(t.Integer, t.Fun(t.Var(0), t.Var(1), t.Var(2)))),
      "12",
      "",
    )),
  )
}

pub fn recursive_function_test() {
  "!fix((self, n) -> {
    match !int_compare(n, 0) {
      Gt(_) -> { !int_multiply(n, self(!int_subtract(n, 1))) }
      | (_) -> { 1 }
    }
  })"
  |> calc(t.Empty)
  |> list.first
  |> should.equal(Ok(ok("(Integer) -> Integer", "")))
}

// Applying the self reference runs the constructor again, so an effectful
// constructor performs its effects on every recursive call, where the type of
// the built function does not describe them. The constructor has to be pure.
pub fn fix_of_effectful_constructor_test() {
  "!fix((self) -> {
    let _ = perform Log(1)
    let loop = (x) -> { x }
    loop
  })"
  |> calc(t.EffectExtend("Log", #(t.Integer, t.unit), t.Empty))
  |> list.first
  |> should.equal(Ok(#(Error(error.MissingRow("Log")), "15", "")))
}

// (x) -<Log String {}, Alert String 0, ..1> List(x)
pub fn perform_test() {
  let state = dict.new()
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

// Check every node: a successful root alone can hide a nested inference error.
fn check_handler(source, effects, expected) {
  let context = j.Context(..j.pure(), eff: effects)
  let analysis =
    source |> parse |> j.check_with_references(context, dict.new(), _)
  j.all_errors(analysis) |> should.equal([])
  j.type_(analysis) |> debug.mono |> should.equal(expected)
}

pub fn deep_handler_removes_repeated_effect_test() {
  check_handler(
    "handle Ping((_, resume) -> { resume(1) }, (_) -> {
      let a = perform Ping({})
      let b = perform Ping({})
      !int_add(a, b)
    })",
    t.Empty,
    "Integer",
  )
}

pub fn deep_handler_shadows_outer_handler_test() {
  check_handler(
    "handle Ping((_, resume) -> { resume(100) }, (_) -> {
      handle Ping((_, resume) -> { resume(1) }, (_) -> {
        let a = perform Ping({})
        let b = perform Ping({})
        !int_add(a, b)
      })
    })",
    t.Empty,
    "Integer",
  )
}

pub fn handler_callback_effect_escapes_test() {
  let source =
    "handle Ping((_, resume) -> {
    resume(perform Ping({}))
  }, (_) -> {
    let a = perform Ping({})
    let b = perform Ping({})
    !int_add(a, b)
  })"
  check_handler(
    source,
    t.EffectExtend("Ping", #(t.unit, t.Integer), t.Empty),
    "Integer",
  )
  let analysis =
    source |> parse |> j.check_with_references(j.pure(), dict.new(), _)
  j.all_errors(analysis)
  |> list.map(fn(entry) { entry.1 })
  |> should.equal([error.MissingRow("Ping")])
}

pub fn deep_handler_preserves_other_effects_test() {
  check_handler(
    "handle Ping((_, resume) -> { resume(1) }, (_) -> {
      let a = perform Ping({})
      let b = perform Other({})
      let c = perform Ping({})
      !int_add(a, !int_add(b, c))
    })",
    t.EffectExtend("Other", #(t.unit, t.Integer), t.Empty),
    "Integer",
  )
}

pub fn returning_deep_resumption_requires_recursive_type_test() {
  let analysis =
    "handle Log((lift, resume) -> { {lift, resume} }, (_) -> {
      perform Log(\"hello\")
    })"
    |> parse
    |> j.check_with_references(j.pure(), dict.new(), _)
  j.all_errors(analysis)
  |> list.map(fn(entry) { entry.1 })
  |> should.equal([error.Recursive])
}

pub fn composed_handlers_keep_reply_and_result_types_linked_test() {
  let source =
    simplifile.read("../../guides/examples/composed_stateful_handlers.eyg")
    |> should.be_ok
  let analysis =
    source |> parse |> j.check_with_references(j.pure(), dict.new(), _)
  j.all_errors(analysis) |> should.equal([])
  let counter = fn(value) {
    t.record([#("state", t.Integer), #("value", value)])
  }
  let result = counter(counter(t.List(t.Integer)))
  j.type_(analysis)
  |> should.equal(
    t.record([#("left_outside", result), #("right_outside", result)]),
  )

  let wrong =
    "let example = "
    <> source
    <> "\n!list_fold(example.left_outside.value.value, \"\", !string_append)"
  let analysis =
    wrong |> parse |> j.check_with_references(j.pure(), dict.new(), _)
  j.all_errors(analysis)
  |> list.any(fn(entry) {
    case entry.1 {
      error.TypeMismatch(t.String, t.Integer)
      | error.TypeMismatch(t.Integer, t.String) -> True
      _ -> False
    }
  })
  |> should.be_true
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

pub fn call_pure_effect_reply_test() {
  let source = "(_) -> { let f = !pure(perform Get({})) f(41) }"
  let assert j.Done(analysis) = j.check(j.pure(), parse(source))
  j.all_errors(analysis) |> should.equal([])

  let assert t.Fun(
    _,
    t.EffectExtend(
      "Get",
      #(t.Record(t.Empty), t.Fun(t.Integer, effects, reply)),
      tail,
    ),
    returned,
  ) = j.poly_type(analysis)
  reply |> should.equal(returned)
  effects |> should.equal(t.Empty)
  tail |> should.equal(t.Empty)
}

pub fn handle_function_reply_test() {
  let source =
    "handle Get((_, resume) -> { resume((x) -> { !int_add(x, 1) }) }, (_) -> {
      let f = !pure(perform Get({}))
      f(41)
    })"
  let assert j.Done(analysis) = j.check(j.pure(), parse(source))
  j.all_errors(analysis) |> should.equal([])
  j.type_(analysis) |> should.equal(t.Integer)
}

pub fn effect_function_reply_is_not_generalised_test() {
  let source =
    "(_) -> {
      let f = !pure(perform Get({}))
      let _ = f(41)
      f(\"wrong argument\")
    }"
  let assert j.Done(analysis) = j.check(j.pure(), parse(source))
  j.all_errors(analysis)
  |> list.map(fn(entry) { entry.1 })
  |> should.equal([error.TypeMismatch(t.String, t.Integer)])
}

pub fn pure_rejects_effectful_functions_test() {
  let programs = [
    #("!pure((x) -> { perform Log(x) })", "Log"),
    #("let f = (x) -> { perform Log(x) } !pure(f)", "Log"),
    #(
      "handle Get((_, resume) -> {
      resume((x) -> { perform Log(x) })
    }, (_) -> { let f = !pure(perform Get({})) f(41) })",
      "Log",
    ),
    #("!pure((_) -> { !never(perform Abort(\"failed\")) })", "Abort"),
  ]
  // An available handler does not make the function itself pure.
  let context = j.pure() |> j.with_effect("Log", t.Integer, t.unit)
  list.each(programs, fn(example) {
    let #(source, effect) = example
    let assert j.Done(analysis) = j.check(context, parse(source))
    j.all_errors(analysis)
    |> list.map(fn(entry) { entry.1 })
    |> list.contains(error.MissingRow(effect))
    |> should.be_true
  })
}

pub fn pure_accepts_internally_handled_effects_test() {
  let source =
    "!pure((x) -> {
      handle Log((message, resume) -> { resume(message) }, (_) -> { perform Log(x) })
    })(41)"
  let assert j.Done(analysis) = j.check(j.pure(), parse(source))
  j.all_errors(analysis) |> should.equal([])
  j.type_(analysis) |> should.equal(t.Integer)
}

pub fn pure_rejects_non_functions_test() {
  let assert j.Done(analysis) = j.check(j.pure(), parse("!pure(41)"))
  let assert [#(_, error.TypeMismatch(t.Integer, t.Fun(..)))] =
    j.all_errors(analysis)
}

pub fn pure_preserves_let_polymorphism_test() {
  let source = "let id = !pure((x) -> { x }) let _ = id(41) id(\"yes\")"
  let assert j.Done(analysis) = j.check(j.pure(), parse(source))
  j.all_errors(analysis) |> should.equal([])
  j.type_(analysis) |> should.equal(t.String)
}

pub fn pure_only_constrains_one_application_test() {
  let source =
    "let f = !pure((x) -> { (_) -> { perform Log(x) } })
    let g = f(41)
    g({})"
  let context = j.pure() |> j.with_effect("Log", t.Integer, t.unit)
  let assert j.Done(analysis) = j.check(context, parse(source))
  j.all_errors(analysis) |> should.equal([])
  j.type_(analysis) |> should.equal(t.unit)

  let assert j.Done(pure_context) = j.check(j.pure(), parse(source))
  j.all_errors(pure_context)
  |> list.map(fn(entry) { entry.1 })
  |> should.equal([error.MissingRow("Log")])
}

pub fn handler_can_call_function_request_test() {
  let source =
    "handle Apply((f, resume) -> { resume(f(41)) }, (_) -> {
      perform Apply((x) -> { !int_add(x, 1) })
    })"
  let assert j.Done(analysis) = j.check(j.pure(), parse(source))
  j.all_errors(analysis) |> should.equal([])
  j.type_(analysis) |> should.equal(t.Integer)
}

pub fn recursive_function_type_is_still_rejected_test() {
  let assert j.Done(analysis) = j.check(j.pure(), parse("(f) -> { f(f) }"))
  j.all_errors(analysis)
  |> list.map(fn(entry) { entry.1 })
  |> should.equal([error.Recursive])
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
  let state = dict.new()
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
      "(\n  (Integer <Bar(↑Integer ↓7), Foo(↑Integer ↓29), ..30>) -> 7\n  <Bar(↑Integer ↓7), Foo(↑Integer ↓29), ..30>,\n) -> 7",
      "",
    ),
    #(Ok(Nil), "(Integer <Bar(↑Integer ↓7)>) -> 7", ""),
    #(Ok(Nil), "7", "Bar(↑Integer ↓7)"),
    #(Ok(Nil), "(Integer <Bar(↑Integer ↓7)>) -> 7", ""),
    #(Ok(Nil), "Integer", ""),
    #(Ok(Nil), "29", "Foo(↑Integer ↓29)"),
    #(
      Ok(Nil),
      "(\n  (Integer <Foo(↑Integer ↓29), Bar(↑Integer ↓7), ..30>) -> 29\n  <Foo(↑Integer ↓29), Bar(↑Integer ↓7), ..30>,\n) -> 29",
      "",
    ),
    #(Ok(Nil), "(Integer <Foo(↑Integer ↓29)>) -> 29", ""),
    #(Ok(Nil), "29", "Foo(↑Integer ↓29)"),
    #(Ok(Nil), "(Integer <Foo(↑Integer ↓29)>) -> 29", ""),
    #(Ok(Nil), "Integer", ""),
  ])
}

pub fn deep_let_test() {
  let wrap = fn(node) { ir.let_("x", ir.integer(0), node) }
  let source = repeat_build(100, ir.variable("x"), wrap)
  let assert j.Done(analysis) = j.check(j.pure(), source)
  assert [] == j.all_errors(analysis)
}

pub fn deep_apply_test() {
  let wrap = fn(node) { ir.lambda("x", ir.apply(node, ir.variable("x"))) }
  let source = repeat_build(100, ir.builtin("int_absolute"), wrap)
  let assert j.Done(analysis) = j.check(j.pure(), source)
  assert [] == j.all_errors(analysis)
}

fn repeat_build(
  times: Int,
  node: ir.Node(a),
  wrap: fn(ir.Node(a)) -> ir.Node(a),
) -> ir.Node(a) {
  case times <= 0 {
    True -> node
    False -> repeat_build(times - 1, wrap(node), wrap)
  }
}
