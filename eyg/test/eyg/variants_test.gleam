import gleam/io
import eyg/ast
import eyg/ast/pattern
import eyg/typer.{infer, init}
import eyg/typer/monotype
import eyg/typer/polytype.{State}

pub fn infer_variant_test() {
  let typer = init([])
  let untyped =
    ast.Name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.Call(ast.Constructor("Boolean", "True"), ast.Tuple([])),
    )
  let Ok(#(type_, typer)) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer

  assert monotype.Nominal("Boolean", []) =
    monotype.resolve(type_, substitutions)
}

pub fn infer_concrete_parameterised_variant_test() {
  let typer = init([])
  let untyped =
    ast.Name(
      #(
        "Option",
        #([1], [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))]),
      ),
      ast.Call(ast.Constructor("Option", "Some"), ast.Binary("value")),
    )
  let Ok(#(type_, typer)) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer
  assert monotype.Nominal("Option", [monotype.Binary]) =
    monotype.resolve(type_, substitutions)
}

pub fn infer_unspecified_parameterised_variant_test() {
  let typer = init([])
  let untyped =
    ast.Name(
      #(
        "Option",
        #([1], [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))]),
      ),
      ast.Call(ast.Constructor("Option", "None"), ast.Tuple([])),
    )
  let Ok(#(type_, typer)) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer
  assert monotype.Nominal("Option", [monotype.Unbound(_)]) =
    monotype.resolve(type_, substitutions)
}

pub fn unknown_named_type_test() {
  let typer = init([])
  let untyped = ast.Call(ast.Constructor("Foo", "X"), ast.Tuple([]))
  let Error(#(reason, _state)) = infer(untyped, typer)
  assert typer.UnknownType("Foo") = reason
}

pub fn unknown_variant_test() {
  let typer = init([])
  let untyped =
    ast.Name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.Call(ast.Constructor("Boolean", "Perhaps"), ast.Tuple([])),
    )
  let Error(#(reason, _state)) = infer(untyped, typer)
  assert typer.UnknownVariant("Perhaps", "Boolean") = reason
}

pub fn duplicate_variant_test() {
  let typer = init([])
  let untyped =
    ast.Name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.Name(
        #(
          "Boolean",
          #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
        ),
        ast.Binary(""),
      ),
    )
  let Error(#(reason, _state)) = infer(untyped, typer)
  assert typer.DuplicateType("Boolean") = reason
}

pub fn mismatched_inner_type_test() {
  let typer = init([])
  let untyped =
    ast.Name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.Call(ast.Constructor("Boolean", "True"), ast.Binary("")),
    )
  let Error(#(reason, _state)) = infer(untyped, typer)
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
    ast.Name(
      #(
        "Option",
        #([1], [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))]),
      ),
      ast.Case(
        "Option",
        ast.Variable("x"),
        [
          #("Some", "x", ast.Variable("x")),
          #("None", "_", ast.Binary("default")),
        ],
      ),
    )
  let Ok(#(type_, typer)) = infer(untyped, typer)
  let State(substitutions: substitutions, ..) = typer
  assert monotype.Binary = monotype.resolve(type_, substitutions)
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
    ast.Name(
      #(
        "Option",
        #([1], [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))]),
      ),
      ast.Case(
        "Option",
        ast.Variable("x"),
        [#("Some", "z", ast.Variable("z")), #("None", "_", ast.Tuple([]))],
      ),
    )
  let Error(#(reason, _state)) = infer(untyped, typer)
  assert typer.UnmatchedTypes(monotype.Binary, monotype.Tuple([])) = reason
}

pub fn case_of_unknown_type_test() {
  let typer = init([])
  let untyped = ast.Case("Foo", ast.Variable("x"), [])
  let Error(#(reason, _state)) = infer(untyped, typer)
  assert typer.UnknownType("Foo") = reason
}

pub fn missmatched_case_subject_test() {
  let typer = init([])
  let untyped =
    ast.Name(
      #(
        "Option",
        #([1], [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))]),
      ),
      ast.Case("Option", ast.Binary(""), []),
    )
  let Error(#(reason, _state)) = infer(untyped, typer)
  assert typer.UnmatchedTypes(
    monotype.Nominal("Option", [monotype.Unbound(_)]),
    monotype.Binary,
  ) = reason
}

pub fn missmatched_nominal_case_subject_test() {
  let typer = init([])
  let untyped =
    ast.Name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.Name(
        #(
          "Option",
          #(
            [1],
            [#("Some", monotype.Unbound(1)), #("None", monotype.Tuple([]))],
          ),
        ),
        ast.Case(
          "Option",
          ast.Call(ast.Constructor("Boolean", "True"), ast.Tuple([])),
          [],
        ),
      ),
    )
  let Error(#(reason, _state)) = infer(untyped, typer)
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
    ast.Name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.Case(
        "Boolean",
        ast.Variable("x"),
        [#("Perhaps", "_", ast.Binary("value"))],
      ),
    )
  let Error(#(reason, _state)) = infer(untyped, typer)
  assert typer.UnknownVariant("Perhaps", "Boolean") = reason
}

pub fn duplicate_clause_test() {
  let typer =
    init([#("x", polytype.Polytype([], monotype.Nominal("Boolean", [])))])
  let untyped =
    ast.Name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.Case(
        "Boolean",
        ast.Variable("x"),
        [
          #("True", "_", ast.Binary("value")),
          #("True", "_", ast.Binary("repeated")),
        ],
      ),
    )
  let Error(#(reason, _state)) = infer(untyped, typer)
  assert typer.RedundantClause("True") = reason
}

pub fn unhandled_variants_test() {
  let typer =
    init([#("x", polytype.Polytype([], monotype.Nominal("Boolean", [])))])
  let untyped =
    ast.Name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.Case(
        "Boolean",
        ast.Variable("x"),
        [#("True", "_", ast.Binary("value"))],
      ),
    )
  let Error(#(reason, _state)) = infer(untyped, typer)
  assert typer.UnhandledVariants(["False"]) = reason
}
// clause after catch all and duplicate catch all, we don't have catch all
