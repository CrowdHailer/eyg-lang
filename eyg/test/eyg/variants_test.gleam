import gleam/io
import eyg/ast
import eyg/ast/pattern
import eyg/typer.{get_type, infer, init}
import eyg/typer/monotype
import eyg/typer/polytype.{State}

pub fn infer_variant_test() {
  let typer = init([])
  let untyped =
    ast.name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.call(ast.constructor("Boolean", "True"), ast.tuple_([])),
    )
  let #(type_, typer) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer

  let Ok(type_) = get_type(type_)
  assert monotype.Nominal("Boolean", []) =
    monotype.resolve(type_, substitutions)
}

pub fn infer_concrete_parameterised_variant_test() {
  let typer = init([])
  let untyped =
    ast.name(
      #(
        "Option",
        #([1], [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))]),
      ),
      ast.call(ast.constructor("Option", "Some"), ast.binary("value")),
    )
  let #(type_, typer) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(type_)
  assert monotype.Nominal("Option", [monotype.Binary]) =
    monotype.resolve(type_, substitutions)
}

pub fn infer_unspecified_parameterised_variant_test() {
  let typer = init([])
  let untyped =
    ast.name(
      #(
        "Option",
        #([1], [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))]),
      ),
      ast.call(ast.constructor("Option", "None"), ast.tuple_([])),
    )
  let #(type_, typer) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(type_)
  assert monotype.Nominal("Option", [monotype.Unbound(_)]) =
    monotype.resolve(type_, substitutions)
}

pub fn unknown_named_type_test() {
  let typer = init([])
  let untyped = ast.constructor("Foo", "X")
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.UnknownType("Foo") = reason
}

pub fn unknown_variant_test() {
  let typer = init([])
  let untyped =
    ast.name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.constructor("Boolean", "Perhaps"),
    )
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.UnknownVariant("Perhaps", "Boolean") = reason
}

pub fn duplicate_variant_test() {
  let typer = init([])
  let untyped =
    ast.name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.name(
        #(
          "Boolean",
          #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
        ),
        ast.binary(""),
      ),
    )
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.DuplicateType("Boolean") = reason
}

pub fn mismatched_inner_type_test() {
  let typer = init([])
  let untyped =
    ast.name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.call(ast.constructor("Boolean", "True"), ast.binary("")),
    )
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.UnmatchedTypes(monotype.Tuple([]), monotype.Binary) = reason
}

// TODO pattern destructure OR case
// sum types don't need to be nominal, Homever there are very helpful to label the alternatives and some degree of nominal typing is useful for global look up
// pub fn true(x) {
//   fn(a, b) {a(x)}
// }
// pub fn false(x) {
//   fn(a, b) {b(x)}
// }
// fn main() { 
//   let bool = case 1 {
//     1 -> true([])
//     2 -> false([])
//   }
//   let r = bool(fn (_) {"hello"}, fn (_) {"world"})
// }
pub fn case_test() {
  let typer =
    init([
      // TODO need a set variable option so that we have have free variables in the env
      #(
        "x",
        polytype.Polytype([], monotype.Nominal("Option", [monotype.Binary])),
      ),
    ])
  let untyped =
    ast.name(
      #(
        "Option",
        #([1], [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))]),
      ),
      ast.case_(
        "Option",
        ast.variable("x"),
        [
          #("Some", "x", ast.variable("x")),
          #("None", "_", ast.binary("default")),
        ],
      ),
    )
  let #(typed, typer) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)

  assert monotype.Binary =
    monotype.resolve(type_, substitutions)
    |> io.debug()
}

pub fn mismatched_return_in_case_test() {
  let typer =
    init([
      // TODO need a set variable option so that we have have free variables in the env
      #(
        "x",
        polytype.Polytype([], monotype.Nominal("Option", [monotype.Binary])),
      ),
    ])
  let untyped =
    ast.name(
      #(
        "Option",
        #([1], [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))]),
      ),
      ast.case_(
        "Option",
        ast.variable("x"),
        [#("Some", "z", ast.variable("z")), #("None", "_", ast.tuple_([]))],
      ),
    )
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.UnmatchedTypes(monotype.Binary, monotype.Tuple([])) = reason
}

pub fn case_of_unknown_type_test() {
  let typer = init([])
  let untyped = ast.case_("Foo", ast.variable("x"), [])
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.UnknownType("Foo") = reason
}

pub fn missmatched_case_subject_test() {
  let typer = init([])
  let untyped =
    ast.name(
      #(
        "Option",
        #([1], [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))]),
      ),
      ast.case_("Option", ast.binary(""), []),
    )
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.UnmatchedTypes(
    monotype.Nominal("Option", [monotype.Unbound(_)]),
    monotype.Binary,
  ) = reason
}

pub fn missmatched_nominal_case_subject_test() {
  let typer = init([])
  let untyped =
    ast.name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.name(
        #(
          "Option",
          #(
            [1],
            [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))],
          ),
        ),
        ast.case_(
          "Option",
          ast.call(ast.constructor("Boolean", "True"), ast.tuple_([])),
          [],
        ),
      ),
    )
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.UnmatchedTypes(
    monotype.Nominal("Option", [monotype.Unbound(_)]),
    monotype.Nominal("Boolean", []),
  ) = reason
}

// TODO missmatched parameters length -> not sure how that can ever happen if the name has been accepted
pub fn unknown_variant_in_clause_test() {
  let typer =
    init([#("x", polytype.Polytype([], monotype.Nominal("Boolean", [])))])
  let untyped =
    ast.name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.case_(
        "Boolean",
        ast.variable("x"),
        [#("Perhaps", "_", ast.binary("value"))],
      ),
    )
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.UnknownVariant("Perhaps", "Boolean") = reason
}

pub fn duplicate_clause_test() {
  let typer =
    init([#("x", polytype.Polytype([], monotype.Nominal("Boolean", [])))])
  let untyped =
    ast.name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.case_(
        "Boolean",
        ast.variable("x"),
        [
          #("True", "_", ast.binary("value")),
          #("True", "_", ast.binary("repeated")),
        ],
      ),
    )
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.RedundantClause("True") = reason
}

pub fn unhandled_variants_test() {
  let typer =
    init([#("x", polytype.Polytype([], monotype.Nominal("Boolean", [])))])
  let untyped =
    ast.name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.case_(
        "Boolean",
        ast.variable("x"),
        [#("True", "_", ast.binary("value"))],
      ),
    )
  let #(typed, _state) = infer(untyped, typer)
  let Error(reason) = get_type(typed)
  assert typer.UnhandledVariants(["False"]) = reason
}
// clause after catch all and duplicate catch all, we don't have catch all
