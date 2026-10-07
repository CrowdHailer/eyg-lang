import eyg/compiler/sql
import eyg/interpreter/expression
import eyg/interpreter/value as v
import eyg/parser
import gleam/list

fn plan(source) {
  let assert Ok(source) = parser.all_from_string(source)
  let assert Ok(v.Table(facts, rules)) = expression.execute(source, [])
  sql.plan(facts, rules)
}

fn statements(plan: sql.Plan) {
  list.map(plan.rules, fn(rule) { rule.statement })
}

pub fn clauses_become_joins_test() {
  let assert Ok(plan) =
    plan(
      "@{ rule Out({title, director}) {
        var movie var title var person var director
        Movie({id: movie, title, year: 1987}),
        Directed({movie, person}),
        Person({id: person, name: director})
      } }",
    )
  assert plan.relations == [sql.Relation("Out", ["director", "title"])]
  assert statements(plan)
    == [
      sql.Statement(
        "INSERT OR IGNORE INTO temp.\"Out\" (\"director\", \"title\") SELECT DISTINCT t2.\"name\", t0.\"title\" FROM \"Movie\" AS t0, \"Directed\" AS t1, \"Person\" AS t2 WHERE t0.\"year\" = ? AND t1.\"movie\" = t0.\"id\" AND t2.\"id\" = t1.\"person\"",
        [sql.Integer(1987)],
      ),
    ]
  let assert [sql.Rule(reads: ["Person", "Directed", "Movie"], head: "Out", ..)] =
    plan.rules
}

pub fn captured_values_and_helpers_are_inlined_test() {
  let assert Ok(plan) =
    plan(
      "let make = (n) -> { (x) -> { !int_add(x, n) } }
      let later = (year) -> {
        match !int_compare(year, 1990) { Gt(_) -> { True({}) } | (_) -> { False({}) } }
      }
      let name = \"Alien\"
      @{ rule Out({next: make(1)(year)}) {
        var year
        Movie({title: name, year}),
        later(year)
      } }",
    )
  assert statements(plan)
    == [
      sql.Statement(
        "INSERT OR IGNORE INTO temp.\"Out\" (\"next\") SELECT DISTINCT (t0.\"year\" + ?) FROM \"Movie\" AS t0 WHERE t0.\"title\" = ? AND (t0.\"year\" > ?)",
        [
          sql.Integer(1),
          sql.Text("Alien"),
          sql.Integer(1990),
        ],
      ),
    ]
}

pub fn repeated_variables_compare_columns_test() {
  let assert Ok(plan) =
    plan("@{ rule Loop({node}) { var node Edge({from: node, to: node}) } }")
  assert statements(plan)
    == [
      sql.Statement(
        "INSERT OR IGNORE INTO temp.\"Loop\" (\"node\") SELECT DISTINCT t0.\"from\" FROM \"Edge\" AS t0 WHERE (t0.\"from\" = t0.\"to\")",
        [],
      ),
    ]
}

pub fn inline_facts_are_seeded_test() {
  let assert Ok(plan) =
    plan(
      "@{ fact Edge({from: \"A\", to: \"B\"}), fact Edge({from: \"A\", to: \"B\"}) }",
    )
  assert plan.relations == [sql.Relation("Edge", ["from", "to"])]
  assert plan.seeds
    == [
      sql.Statement(
        "INSERT OR IGNORE INTO temp.\"Edge\" (\"from\", \"to\") VALUES (?, ?)",
        [sql.Text("A"), sql.Text("B")],
      ),
    ]
}

pub fn rules_that_cannot_fire_have_no_statement_test() {
  let assert Ok(plan) = plan("@{ rule Out({n: 1}) { False({}) } }")
  assert plan.rules == []
}

pub fn identifiers_are_quoted_test() {
  assert sql.identifier("ta\"ble") == "\"ta\"\"ble\""
}

pub fn values_without_a_sql_type_are_rejected_test() {
  let assert Error(_) = plan("@{ fact Out({items: [1, 2]}) }")
  let assert Error(_) =
    plan("@{ rule Out({n}) { var n Input({n}), !int_parse(\"1\") } }")
}

pub fn negated_conditions_test() {
  let assert Ok(plan) =
    plan(
      "let not = (b) -> { match b { True(_) -> { False({}) } False(_) -> { True({}) } } }
      @{ rule Pair({actor, other}) {
        var movie var actor var other
        Cast({movie, actor}), Cast({movie, actor: other}), not(!equal(actor, other))
      } }",
    )
  assert statements(plan)
    == [
      sql.Statement(
        "INSERT OR IGNORE INTO temp.\"Pair\" (\"actor\", \"other\") SELECT DISTINCT t0.\"actor\", t1.\"actor\" FROM \"Cast\" AS t0, \"Cast\" AS t1 WHERE t1.\"movie\" = t0.\"movie\" AND NOT (t0.\"actor\" = t1.\"actor\")",
        [],
      ),
    ]
}
