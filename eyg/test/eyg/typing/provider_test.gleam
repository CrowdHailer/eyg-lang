import gleam/io
import gleam/option.{Some}
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer/monotype as t
import eyg/typer
import eyg/analysis
import eyg/editor/editor

pub fn unable_to_generate_test() {
  let source = e.provider("", e.Example)
  let constraint = t.Record([], Some(-1))
  let #(typed, typer) = analysis.infer(source, constraint, [])
  let #(xtyped, typer) = typer.expand_providers(typed, typer, [])

  assert [#([], typer.ProviderFailed(_, _))] = typer.inconsistencies

  let constraint = t.Tuple([t.Unbound(-1), t.Unbound(-2)])
  let #(typed, typer) = analysis.infer(source, constraint, [])
  let #(xtyped, typer) = typer.expand_providers(typed, typer, [])
  let type_ = analysis.get_type(xtyped, typer)
  assert Ok(t.Tuple([t.Binary, t.Binary])) = type_
}

pub fn type_provider_test() {
  let source = e.call(e.provider("", e.Type), e.binary("Foo"))
  let constraint = t.Unbound(-1)

  let #(typed, typer) = analysis.infer(source, constraint, [])
  let #(xtyped, typer) = typer.expand_providers(typed, typer, [])
  let type_ = analysis.get_type(xtyped, typer)
  assert Ok(t.Union([#("Binary", t.Tuple([]))], Some(0))) = type_
}

pub fn bad_tuple_test() {
  let source = e.call(e.provider("", e.BadTuple), e.binary("Foo"))
  let constraint = t.Unbound(-1)

  let #(typed, typer) = analysis.infer(source, constraint, [])
  let #(xtyped, typer) = typer.expand_providers(typed, typer, [])
  assert editor.Expression(prov) = editor.get_element(xtyped, [0])
  let type_ = analysis.get_type(prov, typer)
  assert Error(_) = type_
  //  assert Ok(t.Union([#("Binary", t.Tuple([]))], Some(0))) = type_
  //  todo("flunk")
}
