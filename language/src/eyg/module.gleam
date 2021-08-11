import gleam/io
import gleam/list
import gleam/string
import language/type_.{Data, Function, PolyType, Variable}
import language/codegen/javascript
import language/ast
import language/scope
import language/ast/builder.{
  binary, call, case_, constructor as variant, destructure_tuple, function, let_,
  row, tuple_, var, varient as name,
}
import eyg/list as eyg_list

// probably just call type
fn monotype() {
  name(
    "eyg_ir_type_Type",
    [],
    [
      variant("Nominal", [Data("String", []), Data("eyg_ir_type_Type", [])]),
      variant("Tuple", [Data("List", [Data("eyg_ir_type_Type", [])])]),
      variant("Row", [Data("List", [Data("eyg_ir_type_Type", [])])]),
      variant(
        "Function",
        [
          Data("List", [Data("eyg_ir_type_Type", [])]),
          Data("eyg_ir_type_Type", []),
        ],
      ),
      variant("Unbound", [Data("Int", [])]),
    ],
    seq(
      [
        // names, next substitutions
        #("checker", tuple_([empty(), zero(), empty()])),
        #("next_unbound", function(["checker"], seq([], var("checker")))),
        #(
          "unify_test",
          function(
            [],
            seq(
              [
                //   TODO sequence takes pattern
                #("typer", var("checker")),
                #("t1", call(var("next_unbound"), [var("checker")])),
              ],
              call(var("should.equal"), [var("t1"), var("t1")]),
            ),
          ),
        ),
      ],
      tuple_([var("unify_test")]),
    ),
  )
}

// variant with a is the correct spelling
fn module() {
  name(
    "Boolean",
    [],
    [variant("True", []), variant("False", [])],
    destructure_tuple(
      ["list$Cons", "list$Nil", "list$reverse", "list$map"],
      eyg_list.return_tuple(),
      destructure_tuple(
        ["unify_test"],
        monotype(),
        row([
          test(
            "hello_world",
            call(
              var("should.equal"),
              [binary("Hello, World!"), binary("Hello, World!")],
            ),
          ),
          named_test("unify_test"),
        ]),
      ),
    ),
  )
}

fn named_test(name) {
  #(name, var(name))
}

fn test(name, body) {
  #(string.concat([name, "_test"]), function([], body))
}

fn seq(matches, last) {
  case matches {
    [] -> last
    [#(pattern, value), ..matches] -> let_(pattern, value, seq(matches, last))
  }
}

fn zero() {
  call(var("zero"), [])
}

fn empty() {
  call(var("list$Nil"), [])
}

pub fn compiled() {
  // This can be built atop equal
  assert #(scope, #("should.equal", 1)) =
    scope.new()
    |> scope.set_variable(
      "should.equal",
      PolyType([1], Function([Variable(1), Variable(1)], Data("Boolean", []))),
    )
  assert #(scope, #("equal", 1)) =
    scope
    |> scope.set_variable(
      "equal",
      PolyType([1], Function([Variable(1), Variable(1)], Data("Boolean", []))),
    )
  assert #(scope, #("zero", 1)) =
    scope
    |> scope.set_variable("zero", PolyType([], Function([], Data("Int", []))))

  case ast.infer(module(), scope) {
    Ok(#(type_, tree, substitutions)) ->
      javascript.maybe_wrap_expression(#(type_, tree))
      |> list.intersperse("\n")
      |> string.concat()
    Error(info) -> {
      io.debug(ast.failure_to_string(info))
      todo("FAILED TO COMPILE")
    }
  }
}
