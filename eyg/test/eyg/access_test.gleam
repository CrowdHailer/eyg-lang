import gleam/option.{Some}
import gleam/io
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer/monotype as t
import eyg/analysis
import platform/browser

pub fn access_record_literal_test() {
  let source = e.access(e.record([#("foo", e.binary("bar"))]), "foo")
  let #(typed, checker) = analysis.infer(source, t.Unbound(-1), [])
  assert [] = checker.inconsistencies

  assert Ok(t.Binary) = analysis.get_type(typed, checker)
}

pub fn access_variable_test() {
  let source = e.function(p.Variable("x"), e.access(e.variable("x"), "foo"))
  let #(typed, checker) = analysis.infer(source, t.Unbound(-1), [])
  assert [] = checker.inconsistencies
  assert Ok(t.Function(from, to, _)) = analysis.get_type(typed, checker)

  assert t.Record(fields: [#("foo", t.Unbound(i: 0))], extra: Some(1)) = from
  assert t.Unbound(i: 0) = to
}
