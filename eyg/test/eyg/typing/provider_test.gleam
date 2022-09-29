import gleam/io
import gleam/option.{None, Some}
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

pub fn empty_list_provider_test() {
  let source = e.call(e.provider("", e.List), e.tuple_([]))
  // TODO move to type lib
  let constraint = t.Recursive(0, t.Union([#("Nil", t.Tuple([]))], None))

  let #(typed, typer) = analysis.infer(source, constraint, [])
  let #(xtyped, typer) = typer.expand_providers(typed, typer, [])
  assert [] = typer.inconsistencies
  // io.debug(xtyped)
  // let type_ =
  //   analysis.get_type(xtyped, typer)
  //   |> io.debug
  // assert Ok(t.Union([#("Binary", t.Tuple([]))], Some(0))) = type_
}

pub fn list_provider_test() {
  let source =
    e.call(e.provider("", e.List), e.tuple_([e.binary("foo"), e.binary("bar")]))
  // TODO move to type lib
  let constraint =
    t.Recursive(
      0,
      t.Union(
        [
          #("Nil", t.Tuple([])),
          #("Cons", t.Tuple([t.Unbound(1), t.Unbound(0)])),
        ],
        None,
      ),
    )

  let #(typed, typer) = analysis.infer(source, constraint, [])
  let #(xtyped, typer) = typer.expand_providers(typed, typer, [])
  assert [] = typer.inconsistencies
  let type_ = analysis.get_type(xtyped, typer)
  assert Ok(t.Recursive(
    0,
    t.Union(
      [#("Nil", t.Tuple([])), #("Cons", t.Tuple([t.Binary, t.Unbound(0)]))],
      None,
    ),
  )) = type_
}
