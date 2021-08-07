import gleam/option.{None}
import language/ast/builder.{
  binary, call, case_, constructor, destructure, function, let_, row, tuple_, var,
  varient,
}
import language/ast.{Assignment, CaseClause, Destructure, ValueDestructuring}
import language/type_.{
  CouldNotUnify, IncorrectArity, RedundantClause, UnhandledVarients, UnknownVariable,
}
import language/scope
import language/type_.{Data, Row}
import language/ast/support

pub fn infer_type_constructor_for_var_test() {
  let untyped = let_("foo", binary("abc"), var("foo"))
  let Ok(#(type_, _, _)) = ast.infer(untyped, scope.new())
  // seems not to be ok as assert
  let Data("Binary", []) = type_
}

pub fn infer_type_constructor_for_tuple_test() {
  let untyped = let_("foo", tuple_([binary("aaa"), tuple_([])]), var("foo"))
  let Ok(#(type_, _, _)) = ast.infer(untyped, scope.new())
  // seems not to be ok as assert
  let Data("Tuple", [Data("Binary", []), Data("Tuple", [])]) = type_
}

pub fn infer_type_constructor_for_row_test() {
  let untyped = let_("user", row([#("name", binary("aaa"))]), var("user"))
  let Ok(#(type_, _, _)) = ast.infer(untyped, scope.new())
  // seems not to be ok as assert
  let Row([#("name", Data("Binary", []))], None) = type_
}

pub fn missing_var_test() {
  let untyped = var("bar")
  let Error(#(failure, situation)) = ast.infer(untyped, scope.new())

  let UnknownVariable("bar") = failure
}

pub fn destructure_test() {
  let scope = scope.new()

  let untyped =
    varient(
      "User",
      [],
      [constructor("User", [Data("Binary", [])])],
      destructure(
        "User",
        ["first_name"],
        call(var("User"), [binary("abc")]),
        var("first_name"),
      ),
    )
  let Ok(#(type_, tree, typer)) = ast.infer(untyped, scope)
  let Data("Binary", []) = type_.resolve_type(type_, typer)
}

pub fn unknown_constructor_test() {
  let untyped = destructure("True", [], binary("abc"), binary("abc"))
  let Error(#(UnknownVariable("True"), _situation)) =
    ast.infer(untyped, scope.new())
}

pub fn incorrect_destructure_arity_test() {
  let scope = scope.new()

  let untyped =
    varient(
      "User",
      [],
      [constructor("User", [Data("Binary", [])])],
      destructure("User", [], call(var("User"), [binary("abc")]), binary("abc")),
    )
  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let IncorrectArity(expected: 1, given: 0) = failure
  let ValueDestructuring("User") = situation
}

pub fn incorrect_destructure_type_test() {
  let scope =
    scope.new()
    |> scope.with_equal()

  let untyped =
    support.with_boolean(varient(
      "User",
      [],
      [constructor("User", [Data("Binary", [])])],
      destructure("True", [], call(var("User"), [binary("abc")]), binary("abc")),
    ))

  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let CouldNotUnify(expected: Data("User", []), given: Data("Boolean", [])) =
    failure
  let ValueDestructuring("True") = situation
}

pub fn multvariant_let_error_test() {
  let scope =
    scope.new()
    |> scope.with_equal()

  let untyped =
    support.with_boolean(destructure(
      "True",
      [],
      call(var("equal"), [binary("abc"), binary("abc")]),
      binary("abc"),
    ))

  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let UnhandledVarients(["False"]) = failure
  let ValueDestructuring("True") = situation
}

pub fn missing_case_error_test() {
  let scope = scope.new()

  let untyped =
    varient(
      "Foo",
      [],
      [constructor("A", []), constructor("B", []), constructor("C", [])],
      function(
        ["x"],
        case_(
          var("x"),
          [
            #(Destructure("A", []), binary("abc")),
            #(Destructure("B", []), binary("abc")),
          ],
        ),
      ),
    )

  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let UnhandledVarients(["C"]) = failure
  let CaseClause = situation
}

pub fn duplicate_case_error_test() {
  let scope = scope.new()

  let untyped =
    varient(
      "Foo",
      [],
      [constructor("A", []), constructor("B", []), constructor("C", [])],
      function(
        ["x"],
        case_(
          var("x"),
          [
            #(Destructure("A", []), binary("abc")),
            #(Destructure("A", []), binary("abc")),
          ],
        ),
      ),
    )

  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let RedundantClause("A") = failure
  let CaseClause = situation
}

pub fn following_catch_all_error_test() {
  let scope = scope.new()

  let untyped =
    varient(
      "Foo",
      [],
      [constructor("A", []), constructor("B", []), constructor("C", [])],
      function(
        ["x"],
        case_(
          var("x"),
          [
            #(Destructure("A", []), binary("abc")),
            #(Assignment("foo"), binary("abc")),
            #(Destructure("B", []), binary("abc")),
          ],
        ),
      ),
    )

  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let RedundantClause("B") = failure
  let CaseClause = situation
}

pub fn duplicate_catch_all_error_test() {
  let scope = scope.new()

  let untyped =
    varient(
      "Foo",
      [],
      [constructor("A", []), constructor("B", []), constructor("C", [])],
      function(
        ["x"],
        case_(
          var("x"),
          [
            #(Destructure("A", []), binary("abc")),
            #(Assignment("foo"), binary("abc")),
            #(Assignment("bar"), binary("abc")),
          ],
        ),
      ),
    )

  let Error(#(failure, situation)) = ast.infer(untyped, scope)
  let RedundantClause("_") = failure
  let CaseClause = situation
}
