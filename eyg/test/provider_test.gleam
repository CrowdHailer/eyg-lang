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

fn id(x) {
  r.Value(x)
}

fn step(path, i) {
  list.append(path, [i])
}

const r_unit = r.Record([])

fn type_to_language_term(type_) {
  case type_ {
    t.Unbound(i) -> r.Tagged("Unbound", r.Integer(i))
    t.Integer -> r.Tagged("Integer", r_unit)
    t.Binary -> r.Tagged("Binary", r_unit)
    t.LinkedList(item) -> r.Tagged("List", type_to_language_term(item))
    t.Fun(from, effects, to) -> {
      let from = type_to_language_term(from)
      let to = type_to_language_term(to)
      r.Tagged("Lambda", r.Record([#("from", from), #("to", to)]))
    }
    t.Record(row) -> r.Tagged("Record", row_to_language_term(row))
    t.Union(row) -> r.Tagged("Union", row_to_language_term(row))
  }
}

fn row_to_language_term(row) {
  todo("row_to_language_term")
}

fn language_term_to_expression(term) -> e.Expression {
  assert r.Tagged(node, inner) = term
  case node {
    "Variable" -> {
      assert r.Binary(value) = inner
      e.Variable(value)
    }
    "Lambda" -> {
      assert r.Record(fields) = inner
      assert Ok(r.Binary(param)) = list.key_find(fields, "label")
      assert Ok(body) = list.key_find(fields, "body")
      e.Lambda(param, language_term_to_expression(body))
    }
    "Binary" -> {
      assert r.Binary(value) = inner
      e.Binary(value)
    }
    "Integer" -> {
      assert r.Integer(value) = inner
      e.Integer(value)
    }
  }
}

// TODO deduplicate fn
fn field(row: t.Row(a), label) {
  case row {
    t.Open(_) | t.Closed -> Error(Nil)
    t.Extend(l, t, _) if l == label -> Ok(t)
    t.Extend(_, _, tail) -> field(tail, label)
  }
}

// call provide and prewalk
// path in interpreter, loader just needs to be near id function and return AST. 
// UI for provider, test with format.

fn do_expand(source, inferred, path, env) {
  case source {
    // e.Let(label, value, then) -> {
    //   let value = do_expand(value, inferred, step(path, 0), env)
    //   //   assert r.Value(term) =
    //   //     r.eval(value, env, id)
    //   //     |> io.debug
    //   let then =
    //     do_expand(then, inferred, step(path, 1), [#(label, value), ..env])
    //   e.Let(label, value, then)
    // }
    // e.Lambda(param, body) -> e.Lambda(param, body)
    // DO we always want a fn probably not
    e.Provider(generator) -> {
      try fit =
        inference.type_of(inferred, path)
        |> result.map_error(fn(_) { todo("this inf error") })
      try needed = case fit {
        t.Union(row) ->
          // TODO ordered fields fn
          field(row, "Ok")
          |> result.map_error(fn(_) { "no Ok field" })

        _ -> Error("not a union")
      }

      io.debug(#("needed", needed))
      assert r.Value(g) = r.eval(generator, [], id)
      assert r.Value(result) = r.eval_call(g, type_to_language_term(needed), id)

      assert r.Tagged(tag, value) = result
      case tag {
        "Ok" -> {
          let generated = language_term_to_expression(value)
          io.debug(#("generated", generated))
          let inferred = inference.infer(map.new(), generated, needed, t.Closed)
          io.debug(inference.sound(inferred))
          let code = case inference.sound(inferred) {
            Ok(Nil) -> e.Apply(e.Tag("Ok"), generated)
            Error(_) -> e.Apply(e.Tag("Error"), e.unit)
          }
          Ok(code)
        }
      }
    }

    //   need env at the time
    e.Vacant -> Ok(e.Vacant)
    _ -> {
      io.debug(source)
      todo("nooooop")
    }
  }
}

fn expand(source, inferred) {
  do_expand(source, inferred, [], [])
}

// e.case and case_of
// builders of eyg versions
// These ast helpers need to end up in the code
fn cast_term(ast) {
  assert r.Value(value) = r.eval(ast, [], id)
  language_term_to_expression(value)
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
  assert r.Value(result) = r.eval_call(g, type_to_language_term(t.Integer), id)
  result
  |> should.equal(r.error(r.Binary("not a lambda")))

  let hole = type_to_language_term(t.Fun(t.Binary, t.Closed, t.Binary))
  assert r.Value(result) = r.eval_call(g, hole, id)
  assert r.Tagged("Ok", code) = result
  // |> should.equal(r.error(r.Binary("not a lambda")))
  code
  |> language_term_to_expression
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
  assert Ok(expanded) = expand(source, inferred)
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
//   // expand(source, inferred)
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
