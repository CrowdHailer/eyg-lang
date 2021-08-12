import gleam/io
import gleam/list
import gleam/string
import language/type_.{Data, Function, PolyType, Variable}
import language/codegen/javascript
import language/ast.{
  Assignment as Var, Destructure as Nominal, TuplePattern as Tuple,
}
import language/scope
import language/ast/builder.{
  binary, call, constructor as variant, destructure_tuple, function, let_, row, tuple_,
  varient as name,
}
import eyg/list as eyg_list
import eyg/helpers.{fun, label_call, seq, test, var, vars}

// probably just call type
fn monotype() {
  name(
    "eyg_ir_type_Type",
    [],
    [
      variant("Nominal", [Data("Binary", []), Data("eyg_ir_type_Type", [])]),
      variant("Tuple", [Data("List", [Data("eyg_ir_type_Type", [])])]),
      //   variant("Tuple", [Data("Int", [])]),
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
        #(Var("checker"), tuple_([empty(), zero(), empty()])),
        fun(
          "next_unbound",
          ["checker"],
          [
            #(Tuple(["names", "next", "substitutions"]), var("checker")),
            #(Var("type"), label_call("Unbound", ["next"])),
            #(Var("next"), label_call("inc", ["next"])),
            #(Var("checker"), tuple_(vars(["names", "next", "substitutions"]))),
          ],
          tuple_([var("type"), var("checker")]),
        ),
        fun(
          "resolve",
          ["type", "checker"],
          [#(Tuple(["names", "next", "substitutions"]), var("checker"))],
          case_(
            var("type"),
            [
              #(
                Nominal("Unbound", ["i"]),
                case_(
                  label_call("list$key_find", ["substitutions", "i"]),
                  [
                    #(Nominal("Ok", ["value"]), var("value")),
                    #(Nominal("Error", ["_"]), var("type")),
                  ],
                ),
              ),
              #(Var("rest"), unimplemented("resolving type")),
            ],
          ),
        ),
        #(
          Var("unify"),
          function(
            ["given", "expected", "checker"],
            seq(
              [
                #(
                  Var("given"),
                  call(var("resolve"), [var("given"), var("checker")]),
                ),
                #(
                  Var("expected"),
                  call(var("resolve"), [var("expected"), var("checker")]),
                ),
                #(Tuple(["names", "next", "substitutions"]), var("checker")),
              ],
              case_(
                call(var("equal"), [var("given"), var("expected")]),
                [
                  #(Nominal("True", []), var("checker")),
                  #(
                    Nominal("False", []),
                    case_(
                      var("given"),
                      [
                        #(
                          Nominal("Unbound", ["i"]),
                          let_(
                            "substitutions",
                            call(
                              var("list$Cons"),
                              [
                                tuple_([var("i"), var("expected")]),
                                var("substitutions"),
                              ],
                            ),
                            tuple_([
                              var("names"),
                              var("next"),
                              var("substitutions"),
                            ]),
                          ),
                        ),
                        #(Var("rest"), unimplemented("unify function")),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        test(
          "unify_variables",
          [
            #(Tuple(["t1", "checker"]), label_call("next_unbound", ["checker"])),
            #(Tuple(["t2", "checker"]), label_call("next_unbound", ["checker"])),
            #(Var("_"), label_call("should.not_equal", ["t1", "t2"])),
            #(Var("checker"), label_call("unify", ["t1", "t2", "checker"])),
          ],
          call(
            var("should.equal"),
            [label_call("resolve", ["t1", "checker"]), var("t2")],
          ),
        ),
        #(
          Var("unify_data_test"),
          function(
            [],
            seq(
              [
                #(
                  Tuple(["t1", "checker"]),
                  call(var("next_unbound"), [var("checker")]),
                ),
              ],
              // #(
              //   Var("my_tuple_type"),
              //   call(var("Tuple"), [call(var("list$Nil"), [])]),
              // ),
              // #(
              //   Var("checker"),
              //   call(
              //     var("unify"),
              //     [var("my_tuple_type"), var("t1"), var("checker")],
              //   ),
              // ),
              // #(
              //   Var("x"),
              //   call(
              //     var("Nominal"),
              //     [binary("jel"), call(var("Row"), [empty()])],
              //   ),
              // ),
              //   binary("WAAT"),
              var("checker"),
            ),
          ),
        ),
      ],
      tuple_([var("unify_variables_test"), var("unify_data_test")]),
    ),
  )
}

fn boolean(then) {
  name("Boolean", [], [variant("True", []), variant("False", [])], then)
}

fn result(then) {
  boolean(name(
    "Result",
    [1, 2],
    [variant("Ok", [Variable(1)]), variant("Error", [Variable(2)])],
    then,
  ))
}

// variant with a is the correct spelling
fn module() {
  result(destructure_tuple(
    list.map(eyg_list.exports(), fn(f) { string.concat(["list$", f]) }),
    eyg_list.return_tuple(),
    destructure_tuple(
      ["unify_variables_test", "unify_data_test"],
      monotype(),
      row([named_test("unify_variables_test"), named_test("unify_data_test")]),
    ),
  ))
}

fn named_test(name) {
  #(name, var(name))
}

pub fn case_(subject, clauses) {
  #(Nil, ast.Case(subject, clauses))
}

fn zero() {
  call(var("zero"), [])
}

fn empty() {
  call(var("list$Nil"), [])
}

fn unimplemented(message) {
  call(var("unimplemented"), [binary(message)])
}

pub fn compiled() {
  // This can be built atop equal
  assert #(scope, #("should.equal", 1)) =
    scope.new()
    |> scope.set_variable(
      "should.equal",
      PolyType([1], Function([Variable(1), Variable(1)], Data("Boolean", []))),
    )
  assert #(scope, #("should.not_equal", 1)) =
    scope
    |> scope.set_variable(
      "should.not_equal",
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
  assert #(scope, #("inc", 1)) =
    scope
    |> scope.set_variable(
      "inc",
      PolyType([], Function([Data("Int", [])], Data("Int", []))),
    )
  assert #(scope, #("unimplemented", 1)) =
    scope
    |> scope.set_variable(
      "unimplemented",
      PolyType([1], Function([Data("Binary", [])], Variable(1))),
    )

  case ast.infer(module(), scope) {
    Ok(#(type_, tree, _substitutions)) ->
      javascript.maybe_wrap_expression(#(type_, tree))
      |> list.intersperse("\n")
      |> string.concat()
    Error(info) -> {
      io.debug(ast.failure_to_string(info))
      todo("FAILED TO COMPILE")
    }
  }
}
