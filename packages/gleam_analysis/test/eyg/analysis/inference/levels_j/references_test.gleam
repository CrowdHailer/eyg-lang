import eyg/analysis/inference/levels_j/contextual as j
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import multiformats/cid/v1

pub fn an_expression_without_references_is_done_test() {
  let assert j.Done(analysis) = j.check(j.pure(), ir.integer(1))
  assert [] == j.all_errors(analysis)
  assert t.Integer == j.type_(analysis)
}

pub fn all_explicit_reference_forms_are_requested_test() {
  references()
  |> list.each(fn(reference) {
    let assert j.Lookup(reference: requested, resume: _) =
      j.check(j.pure(), #(ir.Reference(reference), Nil))
    assert reference == requested
  })
}

pub fn required_references_are_in_source_order_test() {
  let expected = references()
  let source =
    ir.block(
      [
        #("content", reference_node(ir.Content(module()))),
        #("package", reference_node(ir.Package("standard"))),
        #("version", reference_node(ir.Version("standard", 3))),
        #(
          "pinned",
          reference_node(ir.Pinned(ir.Release("standard", 3, another_module()))),
        ),
        #("relative", reference_node(ir.Relative("./module.eyg"))),
      ],
      ir.integer(0),
    )

  assert expected == j.required(j.check(j.pure(), source))
}

pub fn unresolved_forms_have_their_exact_errors_test() {
  let release = ir.Release("standard", 3, module())
  let cases = [
    #(ir.Content(module()), error.MissingReference(module())),
    #(ir.Package("standard"), error.UndefinedPackage("standard")),
    #(ir.Version("standard", 3), error.UndefinedVersion("standard", 3)),
    #(ir.Pinned(release), error.UndefinedRelease(release)),
    #(ir.Relative("./module.eyg"), error.UndefinedRelative("./module.eyg")),
  ]

  cases
  |> list.each(fn(case_) {
    let #(reference, reason) = case_
    let analysis = j.check(j.pure(), reference_node(reference)) |> j.unresolved
    assert [#(Nil, reason)] == j.all_errors(analysis)
  })
}

pub fn analysis_preserves_every_explicit_reference_form_test() {
  references()
  |> list.each(fn(reference) {
    let analysis =
      j.check(j.pure(), reference_node(reference))
      |> j.resolve(fn(requested) {
        assert reference == requested
        Ok(t.Integer)
      })
    assert ir.Reference(reference) == analysis.tree.0
  })
}

pub fn resolver_errors_are_preserved_test() {
  let unavailable = error.MissingVariable("resolver failed")
  let analysis =
    j.check(j.pure(), ir.package("standard"))
    |> j.resolve(fn(_) { Error(unavailable) })

  assert [#(Nil, unavailable)] == j.all_errors(analysis)
  assert ir.Reference(ir.Package("standard")) == analysis.tree.0
}

pub fn a_polymorphic_reference_can_be_reused_at_two_types_test() {
  let identity =
    j.check(j.pure(), ir.lambda("x", ir.variable("x"))) |> j.unresolved
  let source =
    ir.block(
      [
        #("integer", ir.apply(ir.reference(module()), ir.integer(1))),
        #("string", ir.apply(ir.reference(module()), ir.string("hello"))),
      ],
      ir.variable("string"),
    )
  let analysis =
    j.check(j.pure(), source)
    |> j.resolve(fn(_) { Ok(j.poly_type(identity)) })

  assert [] == j.all_errors(analysis)
  assert t.String == j.type_(analysis)
}

pub fn cid_dictionary_adapter_is_intentionally_narrow_test() {
  let available = dict.from_list([#(module(), t.Integer)])

  let content =
    j.check_with_references(j.pure(), available, ir.reference(module()))
  assert [] == j.all_errors(content)
  assert t.Integer == j.type_(content)

  let pinned =
    j.check_with_references(
      j.pure(),
      available,
      ir.release("standard", 3, module()),
    )
  assert [] == j.all_errors(pinned)
  assert t.Integer == j.type_(pinned)

  let unavailable = [
    #(ir.package("standard"), error.UndefinedPackage("standard")),
    #(ir.version("standard", 3), error.UndefinedVersion("standard", 3)),
    #(ir.relative("./module.eyg"), error.UndefinedRelative("./module.eyg")),
  ]
  unavailable
  |> list.each(fn(case_) {
    let #(source, reason) = case_
    let analysis = j.check_with_references(j.pure(), available, source)
    assert [#(Nil, reason)] == j.all_errors(analysis)
  })
}

pub fn missing_concrete_entries_keep_their_explicit_errors_test() {
  let release = ir.Release("standard", 3, another_module())
  let cases = [
    #(
      reference_node(ir.Content(another_module())),
      error.MissingReference(another_module()),
    ),
    #(reference_node(ir.Pinned(release)), error.UndefinedRelease(release)),
  ]

  cases
  |> list.each(fn(case_) {
    let #(source, reason) = case_
    let analysis = j.check_with_references(j.pure(), dict.new(), source)
    assert [#(Nil, reason)] == j.all_errors(analysis)
  })
}

pub fn deeply_nested_reference_resumes_without_javascript_stack_growth_test() {
  let source =
    repeat_build(1000, ir.reference(module()), fn(node) {
      ir.let_("value", ir.integer(1), node)
    })
  let analysis = j.check(j.pure(), source) |> j.unresolved

  assert [#(Nil, error.MissingReference(module()))] == j.all_errors(analysis)
  let assert t.Var(_) = j.type_(analysis)
}

fn references() -> List(ir.Reference) {
  [
    ir.Content(module()),
    ir.Package("standard"),
    ir.Version("standard", 3),
    ir.Pinned(ir.Release("standard", 3, another_module())),
    ir.Relative("./module.eyg"),
  ]
}

fn reference_node(reference) {
  #(ir.Reference(reference), Nil)
}

fn repeat_build(times, node, wrap) {
  case times <= 0 {
    True -> node
    False -> repeat_build(times - 1, wrap(node), wrap)
  }
}

fn module() -> v1.Cid {
  let assert Ok(#(cid, <<>>)) =
    v1.from_string(
      "baguqeeraukgltoe2mhsotqhu7hbeayqkyngmqdgeyphefjcxjmyzevlpdvda",
    )
  cid
}

fn another_module() -> v1.Cid {
  let assert Ok(#(cid, <<>>)) =
    v1.from_string(
      "baguqeerasqnnnjfhwrqmy2ln6yg6d5vlkzsn6vwuvwqfvbxswqvw5xvbrdba",
    )
  cid
}
