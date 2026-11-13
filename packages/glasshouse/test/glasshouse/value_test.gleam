import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/table
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import glasshouse/helpers.{sha256}
import glasshouse/store
import glasshouse/value
import gleam/dict
import multiformats/cid/v1

fn round_trip(input) {
  let encoded = value.encode(input)
  value.decode(encoded, store.new(), Nil)
}

pub fn scalars_round_trip_test() {
  assert round_trip(v.Integer(-42)) == Ok(v.Integer(-42))
  assert round_trip(v.String("hello \"world\""))
    == Ok(v.String("hello \"world\""))
  assert round_trip(v.Binary(<<1, 2, 3>>)) == Ok(v.Binary(<<1, 2, 3>>))
}

pub fn structures_round_trip_test() {
  let input =
    v.Record(
      dict.from_list([
        #("path", v.String("/tmp/a.txt")),
        #("items", v.LinkedList([v.Integer(1), v.Integer(2)])),
        #("result", v.ok(v.Tagged("None", v.unit()))),
      ]),
    )
  assert round_trip(input) == Ok(input)
}

pub fn record_encoding_is_independent_of_insertion_order_test() {
  let a = v.Record(dict.from_list([#("a", v.Integer(1)), #("b", v.Integer(2))]))
  let b = v.Record(dict.from_list([#("b", v.Integer(2)), #("a", v.Integer(1))]))
  assert value.encode(a) == value.encode(b)
}

pub fn records_are_sorted_by_label_test() {
  let record =
    v.Record(dict.from_list([#("z", v.Integer(1)), #("a", v.Integer(2))]))
  let assert #(ir.Apply(#(ir.Apply(#(ir.Extend("a"), _), _), _), _), _) =
    value.encode(record)
}

pub fn partially_applied_tag_round_trips_test() {
  let assert Ok(tag) = round_trip(v.tag("Ok"))
  let assert Ok(applied) = expression.call(tag, [#(v.Integer(3), Nil)])
  assert applied == v.ok(v.Integer(3))
}

pub fn closure_round_trips_test() {
  let source =
    ir.let_(
      "offset",
      ir.integer(10),
      ir.lambda("x", ir.add(ir.variable("x"), ir.variable("offset"))),
    )
    |> ir.map_annotation(fn(_) { Nil })
  let assert Ok(closure) = expression.execute(source, [])
  let assert Ok(decoded) = round_trip(closure)
  let assert Ok(result) = expression.call(decoded, [#(v.Integer(5), Nil)])
  assert result == v.Integer(15)
}

pub fn recorded_masks_and_pure_functions_keep_their_boundaries_test() {
  let assert Ok(mask) = round_trip(v.Partial(v.Mask("Log"), []))
  let assert Ok(callback) =
    expression.execute(
      ir.lambda("_", ir.apply(ir.perform("Log"), ir.integer(42))),
      [],
    )
  let assert Error(#(break.MaskedEffect("Log", v.Integer(42)), _, _, _)) =
    expression.call(mask, [#(callback, Nil)])
  let assert Ok(guarded) =
    expression.call(v.Partial(v.Builtin("pure"), []), [#(callback, Nil)])
  let assert Ok(restored) = round_trip(guarded)
  let assert Error(#(break.ImpureEffect("Log", v.Integer(42)), _, _, _)) =
    expression.call(restored, [#(v.unit(), Nil)])
}

pub fn matching_inlines_content_references_on_both_sides_test() {
  let #(store, id) = store.put_node(store.new(), ir.integer(42), sha256)
  let assert Ok(#(cid, _)) = v1.from_string(id)
  let assert Ok(referenced) =
    expression.execute(ir.lambda("_", ir.reference(cid)), [])
  let assert Ok(literal) =
    expression.execute(ir.lambda("_", ir.integer(42)), [])
  assert value.matches(referenced, value.encode(referenced), store)
  assert value.matches(referenced, value.encode(literal), store)
  assert value.matches(literal, value.encode(referenced), store)
  assert !value.matches(literal, value.encode(referenced), store.new())
}

pub fn externalize_moves_large_binaries_test() {
  let big = v.Binary(<<"0123456789abcdef">>)
  let encoded = value.encode(v.ok(big))
  let #(external, store) = value.externalize(encoded, store.new(), 8, sha256)
  let assert #(ir.Apply(_, #(ir.Reference(ir.Content(_)), _)), _) = external
  assert value.references(external) |> list_length == 1
  assert value.decode(external, store, Nil) == Ok(v.ok(big))
  assert value.inline(external, store) == Ok(encoded)
}

pub fn partially_applied_shallow_handler_round_trips_test() {
  let assert Ok(handler) =
    expression.execute(ir.lambda("_", ir.lambda("_", ir.integer(42))), [])
  let assert Ok(on_return) =
    expression.execute(
      ir.lambda("x", ir.apply(ir.builtin("string_length"), ir.variable("x"))),
      [],
    )
  let assert Ok(restored) =
    round_trip(v.Partial(v.Shallow("Ping"), [handler, on_return]))
  let assert Ok(body) =
    expression.execute(ir.lambda("_", ir.string("hello")), [])
  assert expression.call(restored, [#(body, Nil)]) == Ok(v.Integer(5))
  let assert Ok(body) =
    expression.execute(
      ir.lambda("_", ir.apply(ir.perform("Ping"), ir.unit())),
      [],
    )
  assert expression.call(restored, [#(body, Nil)]) == Ok(v.Integer(42))
}

pub fn externalize_keeps_small_binaries_test() {
  let encoded = value.encode(v.Binary(<<"small">>))
  let #(external, store) = value.externalize(encoded, store.new(), 8, sha256)
  assert external == encoded
  assert store.to_list(store) == []
}

pub fn same_binary_is_stored_once_test() {
  let big = v.Binary(<<"0123456789abcdef">>)
  let encoded = value.encode(v.LinkedList([big, big]))
  let #(_, store) = value.externalize(encoded, store.new(), 8, sha256)
  assert list_length(store.to_list(store)) == 1
}

pub fn matches_compares_with_resolved_references_test() {
  let big = v.Binary(<<"0123456789abcdef">>)
  let #(recorded, store) =
    value.externalize(value.encode(big), store.new(), 8, sha256)
  assert value.matches(big, recorded, store)
  assert !value.matches(v.Binary(<<"other">>), recorded, store)
  assert !value.matches(big, recorded, store.new())
}

pub fn decode_reports_missing_reference_test() {
  let big = v.Binary(<<"0123456789abcdef">>)
  let #(recorded, _) =
    value.externalize(value.encode(big), store.new(), 8, sha256)
  let assert Error(_) = value.decode(recorded, store.new(), Nil)
}

pub fn render_uses_eyg_syntax_test() {
  let input = v.ok(v.Record(dict.from_list([#("name", v.String("pea"))])))
  assert value.render(value.encode(input), store.new()) == "Ok({name: \"pea\"})"
}

fn list_length(items) {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

pub fn query_tables_round_trip_with_stable_relation_order_test() {
  let facts =
    table.from_list([
      #("Z", [v.Integer(2), v.Integer(1)]),
      #("A", [v.String("hello")]),
    ])
  let original = v.Table(facts, [])
  assert round_trip(original) == Ok(original)
  let reordered =
    v.Table(
      table.from_list([
        #("A", [v.String("hello")]),
        #("Z", [v.Integer(2), v.Integer(1)]),
      ]),
      [],
    )
  assert value.encode(original) == value.encode(reordered)
}
