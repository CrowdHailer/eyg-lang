import gleam/dict
import datalog/ast
import datalog/ast/builder.{rule, s, v, y}
import datalog/browser/app/model
import gleeunit/should

pub fn reference_source_in_query_test() {
  let v1 = v("v1")
  let query = [rule("Foo", [v1], [y("Calendar", [v1])])]
  let sections = [
    model.Source("Calendar", ["detail"], [[ast.S("jog")]]),
    model.Query(query, Ok(dict.new())),
  ]
  let assert [source, query_section] = model.run_queries(sections)
  let assert model.Query(_, data) = query_section
  let assert Ok(data) = data
  dict.size(data)
  |> should.equal(2)
  dict.get(data, "Foo")
  |> should.equal(Ok([[ast.S("jog")]]))
}
