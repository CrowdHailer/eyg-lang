import eyg/interpreter/break
import eyg/interpreter/explain
import eyg/interpreter/expression
import eyg/interpreter/proof
import eyg/interpreter/simple_debug
import eyg/interpreter/table
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/list
import gleam/string

fn run(source) {
  let assert Ok(program) = parser.all_from_string(source)
  let assert explain.Completed(Ok(explained), _) =
    explain.start(program, []) |> explain.advance(100_000)
  let assert Ok(ordinary) = expression.execute(program, [])
  assert explained.value == ordinary
  explained
}

pub fn base_facts_have_leaf_proofs_test() {
  let result = run("resolve Item @{fact Item(1), fact Item(1), fact Item(2)}")
  assert result.queries
    == [
      proof.Query("Item", [
        #(v.Integer(1), proof.Fact("Item", v.Integer(1))),
        #(v.Integer(2), proof.Fact("Item", v.Integer(2))),
      ]),
    ]
}

pub fn joins_record_only_the_rows_that_produced_each_answer_test() {
  let result =
    run(
      "resolve Out @{
    fact A({key: 1, value: \"alice\"}), fact A({key: 2, value: \"bob\"}),
    fact B({key: 1, value: \"read\"}), fact B({key: 2, value: \"write\"}),
    rule Out({person, action}) {
      var key var person var action
      A({key, value: person}), B({key, value: action})
    }
  }",
    )
  let assert [proof.Query("Out", answers)] = result.queries
  assert list.length(answers) == 2
  list.each(answers, fn(answer) {
    let assert proof.Rule(
      "Out",
      row,
      0,
      _,
      [proof.Fact("A", a), proof.Fact("B", b)],
    ) = answer.1
    assert row == answer.0
    case simple_debug.inspect(row) {
      "{action: \"read\", person: \"alice\"}" -> {
        assert simple_debug.inspect(a) == "{key: 1, value: \"alice\"}"
        assert simple_debug.inspect(b) == "{key: 1, value: \"read\"}"
      }
      _ -> {
        assert simple_debug.inspect(a) == "{key: 2, value: \"bob\"}"
        assert simple_debug.inspect(b) == "{key: 2, value: \"write\"}"
      }
    }
  })
}

pub fn predicate_proofs_include_actual_bindings_and_source_test() {
  let source =
    "resolve Permit @{
    fact Usage({used: 49}), fact Limit({limit: 50}),
    rule Permit({used, limit}) {
      var used var limit
      Usage({used}), Limit({limit}),
      !equal(!int_compare(used, limit), Lt({}))
    }
  }"
  let result = run(source)
  let assert [proof.Query("Permit", [#(_, tree)])] = result.queries
  let assert proof.Rule(
    "Permit",
    _,
    0,
    _,
    [
      proof.Fact("Usage", _),
      proof.Fact("Limit", _),
      proof.Predicate(at, bindings),
    ],
  ) = tree
  assert list.key_find(bindings, "used") == Ok(v.Integer(49))
  assert list.key_find(bindings, "limit") == Ok(v.Integer(50))
  assert string.slice(source, at.0, at.1 - at.0)
    == "!equal(!int_compare(used, limit), Lt({}))"
}

pub fn failing_predicates_produce_no_answer_or_proof_test() {
  let result =
    run(
      "resolve Out @{
    fact A(1), fact A(2),
    rule Out(x) { var x A(x), !equal(x, 3) }
  }",
    )
  assert result.queries == [proof.Query("Out", [])]
}

pub fn recursive_queries_retain_finite_nested_derivations_test() {
  let result =
    run(
      "resolve Reach @{
    fact Edge({from: \"a\", to: \"b\"}), fact Edge({from: \"b\", to: \"c\"}),
    rule Reach({from, to}) { var from var to Edge({from, to}) }
    rule Reach({from, to}) {
      var from var to var middle
      Reach({from, to: middle}), Edge({from: middle, to})
    }
  }",
    )
  let assert [proof.Query("Reach", answers)] = result.queries
  let assert Ok(#(_, tree)) =
    list.find(answers, fn(answer) {
      simple_debug.inspect(answer.0) == "{from: \"a\", to: \"c\"}"
    })
  let assert proof.Rule(
    "Reach",
    _,
    1,
    _,
    [
      proof.Rule("Reach", _, 0, _, [proof.Fact("Edge", _)]),
      proof.Fact("Edge", _),
    ],
  ) = tree
}

pub fn cycles_and_duplicate_derivations_do_not_grow_proofs_forever_test() {
  let result =
    run(
      "resolve A @{
    fact Seed(1),
    rule A(x) { var x Seed(x) }
    rule A(x) { var x A(x) }
    rule A(x) { var x Seed(x) }
  }",
    )
  let assert [proof.Query("A", [#(_, tree)])] = result.queries
  let assert proof.Rule("A", _, 0, _, [proof.Fact("Seed", v.Integer(1))]) = tree
}

pub fn base_fact_remains_a_leaf_even_if_also_derivable_test() {
  let result = run("resolve A @{fact A(1), rule A(x) {var x A(x)}}")
  assert result.queries
    == [proof.Query("A", [#(v.Integer(1), proof.Fact("A", v.Integer(1)))])]
}

pub fn separate_resolutions_do_not_share_provenance_test() {
  let result =
    run(
      "let first = resolve Out @{fact Input(1), rule Out(x) {var x Input(x)}}
    let second = resolve Out @{fact Input(2), rule Out(x) {var x Input(x)}}
    {first, second}",
    )
  let assert [proof.Query(_, [#(_, first)]), proof.Query(_, [#(_, second)])] =
    result.queries
  let assert proof.Rule(_, _, _, _, [proof.Fact("Input", v.Integer(1))]) = first
  let assert proof.Rule(_, _, _, _, [proof.Fact("Input", v.Integer(2))]) =
    second
}

pub fn failed_matches_do_not_leak_into_a_later_successful_branch_test() {
  let result =
    run(
      "resolve Out @{
    fact A(1), fact A(2),
    rule Out(x) {var x A(x), !equal(x, 2)}
  }",
    )
  let assert [proof.Query("Out", [#(_, tree)])] = result.queries
  let assert proof.Rule(
    _,
    _,
    _,
    _,
    [proof.Fact("A", v.Integer(2)), proof.Predicate(_, bindings)],
  ) = tree
  assert list.key_find(bindings, "x") == Ok(v.Integer(2))
}

pub fn nested_resolutions_keep_their_evidence_separate_test() {
  let result =
    run(
      "resolve Out @{
    fact Outer(1),
    rule Out(resolve Inner @{fact Inner(2)}) { Outer(1) }
  }",
    )
  let assert [
    proof.Query("Inner", [#(_, proof.Fact("Inner", v.Integer(2)))]),
    proof.Query("Out", [#(_, proof.Rule(_, _, _, _, premises))]),
  ] = result.queries
  let assert [proof.Fact("Outer", v.Integer(1)), ..] = premises
}

pub fn host_constructed_constant_table_rule_has_a_zero_premise_witness_test() {
  let constant = v.Table(table.singleton("Out", v.Integer(7)), [])
  let rule =
    v.Closure("_", #(ir.Variable("constant"), #(0, 0)), [
      #("constant", constant),
    ])
  let db = v.Table(dict.new(), [rule])
  let assert Ok(program) = parser.all_from_string("resolve Out db")
  let assert explain.Completed(Ok(result), _) =
    explain.start(program, [#("db", db)]) |> explain.advance(1000)
  let assert [
    proof.Query("Out", [#(v.Integer(7), proof.Rule("Out", _, 0, _, []))]),
  ] = result.queries
}

pub fn matching_a_preconstructed_table_still_records_its_premise_test() {
  let at = #(0, 0)
  let apply = fn(f, arg) { #(ir.Apply(f, arg), at) }
  let body =
    apply(
      apply(
        apply(#(ir.Query(ir.Match("Input", [])), at), #(ir.Variable("db"), at)),
        #(ir.Empty, at),
      ),
      #(ir.Lambda("x", #(ir.Variable("constant"), at)), at),
    )
  let constant = v.Table(table.singleton("Out", v.Integer(7)), [])
  let rule = v.Closure("db", body, [#("constant", constant)])
  let db = v.Table(table.singleton("Input", v.Integer(1)), [rule])
  let assert Ok(program) = parser.all_from_string("resolve Out db")
  let assert explain.Completed(Ok(result), _) =
    explain.start(program, [#("db", db)]) |> explain.advance(1000)
  let assert [
    proof.Query(
      "Out",
      [#(_, proof.Rule("Out", _, 0, _, [proof.Fact("Input", v.Integer(1))]))],
    ),
  ] = result.queries
}

pub fn constant_rules_and_discarded_tables_test() {
  let result = run("resolve Out @{rule Out(let unused = fact Ghost(5) 7) {}}")
  assert result.value == v.LinkedList([v.Integer(7)])
  let assert [proof.Query("Out", [#(_, proof.Rule("Out", _, 0, _, []))])] =
    result.queries
  let ghosts = run("resolve Ghost @{rule Out(let unused = fact Ghost(5) 7) {}}")
  assert ghosts.queries == [proof.Query("Ghost", [])]
}

pub fn suspension_resumes_with_the_same_proof_and_total_step_count_test() {
  let assert Ok(program) =
    parser.all_from_string(
      "resolve Out @{
    fact Input(1), rule Out(x) {var x Input(x)}
  }",
    )
  let start = explain.start(program, [])
  let assert explain.Suspended(_, 0) = explain.advance(start, 0)
  let assert explain.Completed(Ok(expected), total) =
    explain.advance(start, 100_000)
  let assert explain.Suspended(next, spent) = explain.advance(start, total - 1)
  assert spent == total - 1
  let assert explain.Completed(Ok(actual), 1) = explain.advance(next, 1)
  assert actual == expected
}

pub fn effects_still_fail_without_returning_partial_proofs_test() {
  let assert Ok(program) =
    parser.all_from_string(
      "resolve Out @{
    fact Input(1), rule Out(perform Network({})) { Input(1) }
  }",
    )
  let assert explain.Completed(
    Error(#(break.ImpureQuery("Network"), _, _, _)),
    _,
  ) = explain.start(program, []) |> explain.advance(100_000)
}
