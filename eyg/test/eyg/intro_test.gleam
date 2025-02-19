// import eyg/analysis/type_/binding/error
// import eyg/analysis/type_/isomorphic as t
// import eyg/interpreter/value as v
// import website/sync/references.{Store}
// import eygir/annotated
// import gleam/dict
// import gleam/string
// import gleeunit/should
// import intro/snippet

// pub fn simple_assignments_test() {
//   let code =
//     "let x = 1
//   let y = {}"
//   let #(acc, sections) = snippet.process_new([snippet.Text(code)])

//   let snippet.State(_, referenced) = acc
//   let Store(_, values, types) = referenced
//   let assert [snippet] = sections
//   should.equal(snippet.errors, [])
//   let assert [#(1, Ok(ref_x)), #(2, Ok(ref_y))] = snippet.assignments

//   let value_x = should.be_ok(dict.get(values, ref_x))
//   should.equal(value_x, v.Integer(1))
//   let type_x = should.be_ok(dict.get(types, ref_x))
//   should.equal(type_x, t.Integer)

//   let value_y = should.be_ok(dict.get(values, ref_y))
//   should.equal(value_y, v.unit())
//   let type_y = should.be_ok(dict.get(types, ref_y))
//   should.equal(type_y, t.unit)
// }

// pub fn simple_var_test() {
//   let code =
//     "let z = 1
//   let t = z"
//   let #(acc, sections) = snippet.process_new([snippet.Text(code)])
//   let snippet.State(_, referenced) = acc
//   let Store(_, values, types) = referenced

//   let assert [snippet] = sections
//   should.equal(snippet.errors, [])
//   let assert [#(1, Ok(ref_x)), #(2, Ok(ref_y))] = snippet.assignments

//   let value_x = should.be_ok(dict.get(values, ref_x))
//   should.equal(value_x, v.Integer(1))
//   let type_x = should.be_ok(dict.get(types, ref_x))
//   should.equal(type_x, t.Integer)

//   let value_y = should.be_ok(dict.get(values, ref_y))
//   should.equal(value_y, value_x)
//   let type_y = should.be_ok(dict.get(types, ref_y))
//   should.equal(type_y, type_x)
// }

// pub fn known_reference_test() {
//   let pre =
//     e.Apply(e.Tag("Ok"), e.Integer(2))
//     |> annotated.add_annotation(#(0, 0))
//   let assert #([], Ok(#(ref, referenced))) =
//     snippet.install_code(references.empty_cache(), [], pre)

//   let code = "let a = {foo: #foo}" |> string.replace("#foo", "#" <> ref)

//   let #(acc, sections) = snippet.process([snippet.Text(code)], referenced)

//   let snippet.State(_, referenced) = acc
//   let Store(_, values, types) = referenced

//   let assert [snippet] = sections
//   should.equal(snippet.errors, [])
//   let assert [#(1, Ok(ref_a))] = snippet.assignments

//   let value_a = should.be_ok(dict.get(values, ref_a))
//   should.equal(value_a, v.Record([#("foo", v.Tagged("Ok", v.Integer(2)))]))
//   let type_a = should.be_ok(dict.get(types, ref_a))
//   should.equal(
//     type_a,
//     t.Record(t.RowExtend(
//       "foo",
//       t.Union(t.RowExtend("Ok", t.Integer, t.Var(key: #(True, 4)))),
//       t.Empty,
//     )),
//   )
// }

// pub fn type_error_test() {
//   let code = "let f = (_) -> { 3({}) }"
//   let #(acc, sections) = snippet.process_new([snippet.Text(code)])
//   let snippet.State(_, referenced) = acc
//   let Store(_, values, types) = referenced

//   let assert [snippet] = sections
//   let assert [#(error.TypeMismatch(_, t.Integer), _span)] = snippet.errors
//   let assert [#(1, Ok(ref_f))] = snippet.assignments
//   let _value = should.be_ok(dict.get(values, ref_f))
//   let _type = should.be_ok(dict.get(types, ref_f))
// }

// // Test that only the missing variable j is an error as k is something else
// pub fn runtime_error_test() {
//   let code =
//     "let k = j
// let l = k"
//   let #(acc, sections) = snippet.process_new([snippet.Text(code)])
//   let snippet.State(_, referenced) = acc
//   let Store(_, values, types) = referenced

//   let assert [snippet] = sections
//   let assert [#(error.MissingVariable("j"), _span)] = snippet.errors
//   should.equal(dict.size(values), 0)
//   should.equal(dict.size(types), 0)
// }

// fn ref(hash) {
//   e.Reference(hash)
// }

// pub fn replace_test() {
//   let references = [#("a", "123"), #("x", "234"), #("x", "345")]

//   e.Let("x", e.Variable("a"), e.Variable("x"))
//   |> annotated.add_annotation(Nil)
//   |> annotated.substitute_for_references(references)
//   |> annotated.drop_annotation()
//   |> should.equal(e.Let("x", ref("123"), e.Variable("x")))
// }
