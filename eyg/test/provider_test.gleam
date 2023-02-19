import gleam/io
import gleam/list
import gleam/map
import gleam/option.{None, Some}
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/analysis/inference
import eyg/analysis/typ as t
import eyg/provider
import gleam/result
import gleeunit/should

// call provide and prewalk
// path in interpreter, loader just needs to be near id function and return AST.
// UI for provider, test with format.
fn id(x) {
  r.Value(x)
}

// e.case and case_of
// builders of eyg versions
// These ast helpers need to end up in the code
fn cast_term(ast) {
  assert r.Value(value) = r.eval(ast, [], provider.noop, id)
  provider.language_term_to_expression(value)
}

pub fn builder_test() {
  cast_term(provider.binary("foo"))
  |> should.equal(e.Binary("foo"))

  cast_term(provider.integer(5))
  |> should.equal(e.Integer(5))

  cast_term(provider.variable("x"))
  |> should.equal(e.Variable("x"))

  cast_term(provider.lambda("_", provider.integer(0)))
  |> should.equal(e.Lambda("_", e.Integer(0)))
}

// Going direct to string is unnecessay. we probably want to do that direct in eyg and transform here
// to a object for the type
pub fn type_to_string_provider_test() {
  let from_case =
    e.match(
      [
        #("Integer", "_", provider.lambda("_", provider.binary("is integer"))),
        #("Binary", "_", provider.lambda("_", provider.binary("is binary"))),
      ],
      Some(#("_", provider.lambda("_", provider.binary("is other")))),
    )

  // using first class case statement to return fn
  let generator =
    e.match(
      [
        #(
          "Lambda",
          "params",
          e.ok(e.Apply(
            from_case,
            e.Apply(e.Select("from"), e.Variable("params")),
          )),
        ),
      ],
      // TODO I think there is a way I want to see which passes type directly
      Some(#("_", e.error(e.Binary("not a lambda")))),
    )

  let source =
    e.Apply(
      e.match(
        [
          #("Ok", "code", e.Apply(e.Variable("code"), e.Integer(1))),
          #("Error", "_", e.Binary("Nope to compilation")),
        ],
        None,
      ),
      e.Provider(generator),
    )
  let inferred = inference.infer(map.new(), source, t.Binary, t.Closed)
  inference.sound(inferred)
  |> should.equal(Ok(Nil))

  r.eval(source, [], provider.expander(inferred), r.Value)
  |> should.equal(r.Value(r.Binary("is integer")))
}
// pub fn provider_test() {
//   // let source =
//   //   e.Let(
//   //     "make_env",
//   //     e.Vacant,
//   //     e.Let(
//   //       "env",
//   //       e.Apply(e.Provider, e.Variable("make_env")),
//   //       e.Apply(e.Select("foo"), e.Variable("env")),
//   //     ),
//   //   )

//   // // If using external fn then it's needed
//   // let inferred = inference.infer(map.new(), source, t.unit, t.Closed)
//   // //   Doesn't seem to be inferring correctly
//   // inferred.types
//   // //   r.eval(source, [], id)
//   // provider.pre_eval(source, inferred)

//   todo("test")
// }
// values as a func
// constant folding
// Even if we infer the tree then the interpreter will need a reference to run
// OR if we constant fold
// Nested function is a thing so how Generics
// highlighting at each point env at each point
// Should we type check in interpreter only
// e.Let("format", e.Function("initial"), e.Variable("x"))
//   let prog =
//     e.Let(
//       "unit",
//       e.Lambda("type", e.Tag("Empty")),
//       e.Apply(e.Provider, e.Variable("unit")),
//     )
