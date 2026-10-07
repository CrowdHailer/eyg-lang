import eyg/analysis/type_/isomorphic as t
import eyg/compiler/sql
import eyg/ir/tree as ir
import eyg/parser
import gleam/list
import gleam/pair
import gleam/string
import gleeunit/should

@external(javascript, "./sql_ffi.mjs", "run")
fn run(client: String, setup: String, assertions: String) -> String

fn compile(source, relation, sources) {
  source
  |> parser.from_string()
  |> should.be_ok()
  |> pair.first()
  |> sql.to_sql(relation, sources)
  |> should.be_ok()
}

fn edges() {
  sql.Source("Edge", "edges", [
    sql.Column("from", "a", t.String),
    sql.Column("to", "b", t.String),
  ])
}

pub fn static_facts_test() {
  let query = compile("@{ fact Out(1), fact Out(1), fact Out(2) }", "Out", [])
  run(query.javascript, "", "assert.deepEqual(run(db), [1, 2]);")
  |> should.equal("passed")
  string.contains(query.typescript, "export type Row = number;")
  |> should.be_true
}

pub fn recursive_sqlite_query_test() {
  let query =
    compile(
      "@{
      rule Reach({from, to}) { var from var to Edge({from, to}) }
      rule Reach({from, to}) {
        var from var to var middle
        Reach({from, to: middle}), Reach({from: middle, to})
      }
      rule Out({to}) { var to Reach({from: \"A\", to}) }
    }",
      "Out",
      [edges()],
    )
  run(
    query.javascript,
    "CREATE TABLE edges(a TEXT, b TEXT); INSERT INTO edges VALUES ('A','B'), ('B','C'), ('C','A'), ('A','B');",
    "assert.deepEqual(run(db), [{to:'A'}, {to:'B'}, {to:'C'}]);
    db.exec('DELETE FROM edges');
    assert.deepEqual(run(db), []);
    assert.deepEqual(db.prepare('SELECT name FROM sqlite_temp_master').all(), []);
    assert(sql.some(s => s.includes('CROSS JOIN')));",
  )
  |> should.equal("passed")
  string.contains(query.typescript, "\"to\": string") |> should.be_true
}

pub fn captured_functions_and_guards_test() {
  let query =
    compile(
      "let make = (n) -> { (x) -> { !int_add(x, n) } }
    let a = make(1)
    let b = make(10)
    let wanted = 2
    @{
      fact Number(1), fact Number(2), fact Number(3),
      rule Out({a: a(n), b: b(n)}) { var n Number(n), !equal(n, wanted) },
      rule Out({a: 100, b: 100}) { False({}) }
    }",
      "Out",
      [],
    )
  run(query.javascript, "", "assert.deepEqual(run(db), [{a:3,b:12}]);")
  |> should.equal("passed")
}

pub fn mutual_recursion_repeated_variables_and_constants_test() {
  let query =
    compile(
      "let root = \"A\"
    @{
      fact Seen(root),
      rule Next(to) { var from var to Seen(from), Edge({from,to}) },
      rule Seen(to) { var to Next(to) },
      rule Out({node}) { var node Seen(node), Edge({from:node,to:node}) }
    }",
      "Out",
      [edges()],
    )
  run(
    query.javascript,
    "CREATE TABLE edges(a,b); INSERT INTO edges VALUES ('A','B'),('B','C'),('C','A'),('B','B'),('D','D');",
    "assert.deepEqual(run(db), [{node:'B'}]);",
  )
  |> should.equal("passed")
}

pub fn typed_nullable_binary_and_boolean_columns_test() {
  let source =
    sql.Source("Input", "inputs", [
      sql.Column("n", "n", t.Integer),
      sql.Column("text", "text", t.option(t.String)),
      sql.Column("bytes", "bytes", t.Binary),
      sql.Column("flag", "flag", t.boolean),
    ])
  let query =
    compile("@{ rule Out(row) { var row Input(row) } }", "Out", [source])
  run(
    query.javascript,
    "CREATE TABLE inputs(n,text,bytes,flag); INSERT INTO inputs VALUES (7,NULL,x'00ff',0), (8,'hi',x'01',1);",
    "assert.deepEqual(run(db), [
      {n:7,text:{tag:'None',value:{}},bytes:new Uint8Array([0,255]),flag:false},
      {n:8,text:{tag:'Some',value:'hi'},bytes:new Uint8Array([1]),flag:true}
    ]);
    assert.deepEqual(decode(JSON.stringify(['r',[
      ['n',['i',1]], ['text',['t','Some',['s','ok']]], ['bytes',['b',[255]]], ['flag',['t','True',['r',[]]]]
    ]])), {n:1,text:{tag:'Some',value:'ok'},bytes:new Uint8Array([255]),flag:true});",
  )
  |> should.equal("passed")
  string.contains(query.typescript, "\"flag\": boolean") |> should.be_true
  string.contains(query.typescript, "\"bytes\": Uint8Array") |> should.be_true
}

pub fn schema_mismatch_and_unsafe_integer_fail_closed_test() {
  let query =
    compile("@{ rule Out({n}) { var n Input({n}) } }", "Out", [
      sql.Source("Input", "inputs", [sql.Column("n", "n", t.Integer)]),
    ])
  run(
    query.javascript,
    "CREATE TABLE inputs(n);",
    "for (const literal of [\"'oops'\", 'NULL', '1.5', '9223372036854775807']) {
      db.exec(`DELETE FROM inputs; INSERT INTO inputs VALUES (${literal})`);
      assert.throws(() => run(db), /integer|range/);
      assert.deepEqual(db.prepare('SELECT name FROM sqlite_temp_master').all(), []);
      assert.equal(db.prepare('SELECT count(*) AS n FROM inputs').get().n, 1);
    }
    db.exec('DELETE FROM inputs; INSERT INTO inputs VALUES (42)');
    assert.deepEqual(run(db), [{n:42}]);
    for (const wire of [ ['r',[]], ['r', [['n',['s','42']]]], ['r',[['n',['i',1]],['n',['i',2]]]], ['r',[['n',['i',1]],['extra',['i',2]]]] ]) {
      assert.throws(() => decode(JSON.stringify(wire)));
    }",
  )
  |> should.equal("passed")
}

pub fn budgets_rollback_inside_caller_transaction_test() {
  let query =
    compile(
      "@{ fact Number(0), rule Number(!int_add(n,1)) { var n Number(n) } }",
      "Number",
      [],
    )
  run(
    query.javascript,
    "CREATE TABLE host(n); BEGIN; INSERT INTO host VALUES (7);",
    "assert.throws(() => run(db,{maxRounds:3}), /round limit/);
    assert.throws(() => run(db,{maxFacts:3}), /fact limit/);
    assert.throws(() => run(db,{maxRounds:0}), /positive/);
    assert.throws(() => run(db,{maxFacts:1.5}), /positive/);
    assert.deepEqual(db.prepare('SELECT name FROM sqlite_temp_master').all(), []);
    assert.equal(db.prepare('SELECT n FROM host').get().n, 7);
    db.exec('ROLLBACK');
    assert.equal(db.prepare('SELECT count(*) AS n FROM host').get().n, 0);",
  )
  |> should.equal("passed")
}

pub fn identifiers_and_values_are_not_sql_fragments_test() {
  let query =
    compile("@{ rule Out(row) { var row Input(row) } }", "Out", [
      sql.Source("Input", "ta\"ble", [sql.Column("text", "co\"l", t.String)]),
    ])
  run(
    query.javascript,
    "CREATE TABLE \"ta\"\"ble\"(\"co\"\"l\" TEXT); INSERT INTO \"ta\"\"ble\" VALUES ('x''); DROP TABLE host; --'); CREATE TABLE host(n);",
    "assert.deepEqual(run(db), [{text:\"x'); DROP TABLE host; --\"}]);
    assert.equal(db.prepare('SELECT count(*) AS n FROM host').get().n,0);",
  )
  |> should.equal("passed")
}

pub fn compound_set_values_and_lists_test() {
  let query =
    compile(
      "@{
    fact Out({n:1, labels:[\"a\",\"b\"]}),
    fact Out({labels:[\"a\",\"b\"], n:1}),
    rule Out({n:2, labels:[]}) { True({}) }
  }",
      "Out",
      [],
    )
  run(
    query.javascript,
    "",
    "const rows = run(db).sort((a,b) => a.n-b.n);
    assert.deepEqual(rows, [{n:1,labels:['a','b']},{n:2,labels:[]}]);",
  )
  |> should.equal("passed")
}

pub fn rejects_ambiguous_schema_and_non_tables_test() {
  let expression =
    "@{ rule Out(row) { var row Unknown(row) } }"
    |> parser.from_string
    |> should.be_ok
    |> pair.first
  sql.to_sql(expression, "Out", []) |> should.be_error
  sql.to_sql(ir.integer(1), "Out", []) |> should.be_error
  let expression =
    "@{ fact Out(1), rule Out(perform Bad({})) { True({}) } }"
    |> parser.from_string
    |> should.be_ok
    |> pair.first
  sql.to_sql(expression, "Out", []) |> should.be_error
}

pub fn rejects_snapshot_inspection_in_raw_rule_ir_test() {
  let table =
    ir.apply(
      #(ir.Query(ir.Rule), Nil),
      ir.lambda(
        "db",
        ir.apply(
          #(ir.Query(ir.Fact("Out")), Nil),
          ir.apply(#(ir.Query(ir.Resolve("In")), Nil), ir.variable("db")),
        ),
      ),
    )
  sql.to_sql(table, "Out", [
    sql.Source("In", "input", [sql.Column("n", "n", t.Integer)]),
  ])
  |> should.be_error
}

pub fn reserved_fields_and_source_contracts_test() {
  let expression =
    "@{ fact Out(1) }" |> parser.from_string |> should.be_ok |> pair.first
  let invalid_sources = [
    [edges(), edges()],
    [sql.Source("Input", "inputs", [])],
    [
      sql.Source("Input", "inputs", [
        sql.Column("n", "a", t.Integer),
        sql.Column("n", "b", t.String),
      ]),
    ],
    [sql.Source("Input", "inputs", [sql.Column("bad\u{0}", "a", t.String)])],
    [sql.Source("Input", "inputs", [sql.Column("$T", "a", t.String)])],
    [
      sql.Source("Input", "inputs", [
        sql.Column("a", "a", t.option(t.option(t.String))),
      ]),
    ],
  ]
  list.each(invalid_sources, fn(sources) {
    sql.to_sql(expression, "Out", sources) |> should.be_error
  })
}

pub fn record_proto_field_is_data_test() {
  let query = compile("@{ fact Out({__proto__:{n:7}}) }", "Out", [])
  run(
    query.javascript,
    "",
    "const row = run(db)[0];
    assert(Object.hasOwn(row, '__proto__'));
    assert.deepEqual(row.__proto__, {n:7});
    assert.equal(Object.getPrototypeOf(row), Object.prototype);",
  )
  |> should.equal("passed")
}

pub fn boolean_variant_order_does_not_change_client_type_test() {
  let query =
    compile("@{ rule Out(row) { var row Input(row) } }", "Out", [
      sql.Source("Input", "inputs", [
        sql.Column(
          "flag",
          "flag",
          t.union([#("False", t.unit), #("True", t.unit)]),
        ),
      ]),
    ])
  run(
    query.javascript,
    "CREATE TABLE inputs(flag); INSERT INTO inputs VALUES(1);",
    "assert.deepEqual(run(db), [{flag:true}]); db.exec('UPDATE inputs SET flag=2'); assert.throws(() => run(db), /Boolean/);",
  )
  |> should.equal("passed")
  string.contains(query.typescript, "\"flag\": boolean") |> should.be_true
}
