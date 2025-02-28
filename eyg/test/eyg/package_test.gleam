// import eyg/analysis/type_/isomorphic as t
// import eyg/package
// import website/sync/references
// import gleam/dict
// import gleam/io
// import gleeunit/should
// import gleeunit/shouldx
// import morph/editable as e

// pub fn assignments_are_added_to_scope_test() {
//   let cache = references.empty_cache()
//   let snippet = [#(e.Bind("i"), e.Integer(1)), #(e.Bind("s"), e.String("hey"))]
//   let #(cache, computed) = package.load_snippet(snippet, [], cache)
//   let package.Computed(references, errors, final) = computed

//   let #(str, int) = shouldx.contain2(final)
//   let assert #("s", ref) = str
//   references.type_of(cache, ref)
//   |> should.be_ok
//   |> should.equal(t.String)

//   let assert #("i", ref) = int
//   references.type_of(cache, ref)
//   |> should.be_ok
//   |> should.equal(t.Integer)

//   errors
//   |> should.equal([])
// }

// pub fn reference_variables_in_snippet_test() {
//   let cache = references.empty_cache()
//   let snippet = [#(e.Bind("a"), e.Integer(1)), #(e.Bind("b"), e.Variable("a"))]
//   let #(cache, computed) = package.load_snippet(snippet, [], cache)
//   let package.Computed(references, errors, final) = computed

//   let #(second, first) = shouldx.contain2(final)
//   let assert #("a", ref) = first
//   references.type_of(cache, ref)
//   |> should.be_ok
//   |> should.equal(t.Integer)

//   let assert #("b", ref) = second
//   references.type_of(cache, ref)
//   |> should.be_ok
//   |> should.equal(t.Integer)

//   errors
//   |> should.equal([])
// }

// pub fn reference_variables_in_scope_test() {
//   let cache = references.empty_cache()
//   let scope = []

//   let snippet = [#(e.Bind("previous"), e.Integer(1))]
//   let #(cache, computed) = package.load_snippet(snippet, scope, cache)
//   let scope = computed.final

//   let snippet = [#(e.Bind("v"), e.Variable("previous"))]
//   let #(cache, computed) = package.load_snippet(snippet, scope, cache)

//   let package.Computed(references, errors, final) = computed
//   let #(new, previous) = shouldx.contain2(final)
//   let assert #("previous", ref) = previous
//   references.type_of(cache, ref)
//   |> should.be_ok
//   |> should.equal(t.Integer)

//   let assert #("v", ref) = new
//   references.type_of(cache, ref)
//   |> should.be_ok
//   |> should.equal(t.Integer)

//   errors
//   |> should.equal([])
// }

// pub fn require_references_test() {
//   let cache = references.empty_cache()
//   let scope = []

//   let remote_ref = "h123"
//   let snippet = [#(e.Bind("std"), e.Reference(remote_ref))]
//   let #(cache, computed) = package.load_snippet(snippet, scope, cache)
//   let package.Computed(references, errors, final) = computed
//   io.debug(errors)

//   let scope = shouldx.contain1(final)
//   let assert #("std", new_ref) = scope
//   references.expression_for(cache, new_ref)
//   |> should.equal(references.Success(expression.Reference(remote_ref)))

//   references.expression_for(cache, remote_ref)
//   |> should.equal(references.NotAsked)

//   dict.size(cache.values)
//   |> should.equal(0)
//   dict.size(cache.types)
//   |> should.equal(0)
// }
