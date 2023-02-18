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
  assert r.Value(value) = r.eval(ast, [], id)
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

fn match(branches, tail) {
  let final = case tail {
    Some(#(param, body)) -> e.Lambda(param, body)
    None -> e.NoCases
  }
  list.fold_right(
    branches,
    final,
    fn(acc, branch) {
      let #(label, param, then) = branch
      e.Apply(e.Apply(e.Case(label), e.Lambda(param, then)), acc)
    },
  )
}

// Going direct to string is unnecessay. we probably want to do that direct in eyg and transform here
// to a object for the type
pub fn type_string_test() {
  let from_case =
    match(
      [
        #("Integer", "_", provider.lambda("_", provider.binary("is integer"))),
        #("Binary", "_", provider.lambda("_", provider.binary("is binary"))),
      ],
      Some(#("_", provider.lambda("_", provider.binary("is other")))),
    )

  // using first class case statement to return fn
  let generator =
    match(
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
      Some(#("_", e.error(e.Binary("not a lambda")))),
    )

  assert r.Value(g) = r.eval(generator, [], id)
  assert r.Value(result) =
    r.eval_call(g, provider.type_to_language_term(t.Integer), id)
  result
  |> should.equal(r.error(r.Binary("not a lambda")))

  let hole = provider.type_to_language_term(t.Fun(t.Binary, t.Closed, t.Binary))
  assert r.Value(result) = r.eval_call(g, hole, id)
  assert r.Tagged("Ok", code) = result
  // |> should.equal(r.error(r.Binary("not a lambda")))
  code
  |> provider.language_term_to_expression
  |> should.equal(e.Lambda("_", e.Binary("is binary")))
  let source = e.Provider(generator)
  let inferred =
    inference.infer(
      map.new(),
      source,
      t.result(t.Fun(t.Binary, t.Closed, t.Binary), t.Unbound(-1)),
      t.Closed,
    )
  inference.sound(inferred)
  |> should.equal(Ok(Nil))
  assert Ok(expanded) = provider.pre_eval(source, inferred)
  assert r.Value(result) = r.eval(expanded, [], id)
  assert r.Tagged("Ok", program) = result
  r.eval_call(program, r.Integer(1), id)
  |> should.equal(r.Value(r.Binary("is binary")))
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
//   // |> io.debug
//   // //   r.eval(source, [], id)
//   // provider.pre_eval(source, inferred)
//   // |> io.debug

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
