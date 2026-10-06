import eyg/analysis/inference/levels_j/contextual as analysis
import eyg/analysis/type_/binding/debug
import eyg/interpreter/break
import eyg/interpreter/capture
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/json
import gleeunit/should

fn source(text) {
  parser.all_from_string(text) |> should.be_ok()
}

fn check(text) {
  analysis.check_with_references(analysis.pure(), dict.new(), source(text))
}

fn run(text) {
  let checked = check(text)
  analysis.all_errors(checked) |> should.equal([])
  source(text)
  |> expression.execute([])
  |> should.be_ok()
  |> simple_debug.inspect()
}

pub fn fact_composition_and_set_semantics_test() {
  run(
    "let a = fact Item({id: 1})
    resolve Item @{ a, fact Item({id: 2}), a }",
  )
  |> should.equal("[{id: 1}, {id: 2}]")
  run("resolve Missing @{}") |> should.equal("[]")
}

pub fn rule_joins_and_lexical_constants_test() {
  run(
    "let wanted = \"A\"
    resolve Out @{
      fact Edge({from: \"A\", to: \"B\"}),
      fact Edge({from: \"B\", to: \"C\"}),
      rule Out({to}) {
        var middle
        var to
        Edge({from: wanted, to: middle}),
        Edge({from: middle, to}),
        !equal(to, \"C\")
      }
    }",
  )
  |> should.equal("[{to: \"C\"}]")
}

pub fn repeated_variable_filters_within_a_pattern_test() {
  run(
    "resolve Loop @{
    fact Edge({from: 1, to: 2}), fact Edge({from: 2, to: 2}),
    rule Loop(x) { var x Edge({from: x, to: x}) }
  }",
  )
  |> should.equal("[2]")
}

pub fn nested_record_patterns_and_unit_patterns_test() {
  run(
    "resolve Out @{
    fact Input({nested: {id: 2}, extra: 3}),
    rule Out(x) { var x Input({nested: {id: x}}) }
  }",
  )
  |> should.equal("[2]")
  run("resolve Out @{ fact Unit({}), rule Out(1) { Unit({}) } }")
  |> should.equal("[1]")
  check("@{fact Unit(3), rule Out(1) { Unit({}) }}")
  |> analysis.all_errors()
  |> should.not_equal([])
}

pub fn recursive_fixed_point_and_polymorphic_view_test() {
  let view =
    "let view = @{
    rule Reachable({from, to}) { var from var to Edge({from, to}) }
    rule Reachable({from, to}) {
      var from var to var middle
      Edge({from, to: middle}), Reachable({from: middle, to})
    }
  }
  "
  run(view <> "resolve Reachable @{
    view, fact Edge({from: 1, to: 2}), fact Edge({from: 2, to: 1})
  }")
  |> should.equal(
    "[{from: 1, to: 2}, {from: 2, to: 1}, {from: 1, to: 1}, {from: 2, to: 2}]",
  )
  run(view <> "let a = resolve Reachable @{view, fact Edge({from: 1, to: 2})}
    let b = resolve Reachable @{view, fact Edge({from: \"A\", to: \"B\"})}
    {a, b}")
  |> should.equal("{a: [{from: 1, to: 2}], b: [{from: \"A\", to: \"B\"}]}")
}

pub fn pure_head_expressions_and_filters_test() {
  run(
    "let less = (n) -> {
    match !int_compare(n, 3) { Lt(_) -> { True({}) } | (_) -> { False({}) } }
    }
    resolve Number @{
      fact Number(0),
      rule Number(!int_add(n, 1)) { var n Number(n), less(n) }
    }",
  )
  |> should.equal("[0, 1, 2, 3]")
}

pub fn lazy_rule_and_false_predicate_test() {
  source("let unused = rule Out(perform Nope({})) {} 42")
  |> expression.execute([])
  |> should.be_ok()
  |> simple_debug.inspect()
  |> should.equal("42")
  run("resolve Out @{ rule Out(1) { False({}) } }")
  |> should.equal("[]")
}

pub fn rejects_effects_and_inconsistent_relations_test() {
  check("rule Out(perform Nope({})) {}")
  |> analysis.all_errors()
  |> should.not_equal([])
  check("rule Out(1) { perform Nope({}) }")
  |> analysis.all_errors()
  |> should.not_equal([])
  check("@{ fact Edge(1), fact Edge(\"bad\") }")
  |> analysis.all_errors()
  |> should.not_equal([])
  check("rule Out(1) { 123 }")
  |> analysis.all_errors()
  |> should.not_equal([])
}

pub fn query_effect_cannot_escape_to_a_host_or_outer_handler_test() {
  let result =
    source(
      "handle Nope((_, resume) -> { resume(1) }, (_) -> {
    resolve Out @{rule Out(perform Nope({})) {}}
  })",
    )
    |> expression.execute([])
    |> should.be_error()
  result.0 |> should.equal(break.ImpureQuery("Nope"))
}

pub fn table_type_is_distinct_from_record_and_union_test() {
  check("fact Edge({from: 1, to: 2})")
  |> analysis.type_()
  |> debug.mono()
  |> should.equal("Table({Edge: {from: Integer, to: Integer}, ..1})")
  check("resolve Edge {from: 1}")
  |> analysis.all_errors()
  |> should.not_equal([])
}

pub fn capture_and_codec_preserve_rule_closures_test() {
  let program =
    source(
      "let n = 2
    @{fact Input(3), rule Out(!int_add(x, n)) { var x Input(x) }}",
    )
  let value = expression.execute(program, []) |> should.be_ok()
  let captured = capture.capture(value, #(0, 0))
  let encoded = dag_json.to_string(captured)
  let decoded = json.parse(encoded, dag_json.decoder(#(0, 0))) |> should.be_ok()
  expression.execute(
    #(ir.Apply(#(ir.Query(ir.Resolve("Out")), #(0, 0)), decoded), #(0, 0)),
    [],
  )
  |> should.be_ok()
  |> simple_debug.inspect()
  |> should.equal("[5]")
}
