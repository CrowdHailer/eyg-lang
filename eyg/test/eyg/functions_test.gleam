import gleam/io
import gleam/option.{None, Some}
import eyg
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer.{get_type, infer, init}
import eyg/typer/monotype as t
import eyg/typer/monotype.{resolve}
import eyg/typer/polytype

pub fn type_bound_function_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let untyped = ast.function(p.Tuple([]), ast.binary(""))
  let #(typed, typer) = infer(untyped, t.Unbound(-1), #(typer, scope))
  let typer.Typer(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Function(t.Tuple([]), t.Binary) = resolve(type_, substitutions)
}

pub fn generic_function_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let untyped = ast.function(p.Variable("x"), ast.variable("x"))
  let #(typed, typer) = infer(untyped, t.Unbound(-1), #(typer, scope))
  let typer.Typer(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Function(t.Unbound(a), t.Unbound(b)) = resolve(type_, substitutions)
  let True = a == b
}

pub fn call_function_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let untyped =
    ast.call(ast.function(p.Tuple([]), ast.binary("")), ast.tuple_([]))
  let #(typed, typer) = infer(untyped, t.Tuple([]), #(typer, scope))
  let typer.Typer(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Tuple([]) = resolve(type_, substitutions)
}

pub fn call_generic_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let untyped =
    ast.call(
      ast.function(p.Tuple([Some("x")]), ast.variable("x")),
      ast.tuple_([]),
    )
  let #(typed, typer) = infer(untyped, t.Tuple([]), #(typer, scope))
  let typer.Typer(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Tuple([]) = resolve(type_, substitutions)
}

pub fn call_with_incorrect_argument_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let untyped =
    ast.call(
      ast.function(p.Tuple([]), ast.binary("")),
      ast.tuple_([ast.binary("extra argument")]),
    )
  let #(typed, _state) = infer(untyped, t.Tuple([]), #(typer, scope))
  let #(_context, e.Call(_func, with)) = typed
  let Error(reason) = get_type(with)
  let typer.IncorrectArity(0, 1) = reason
}

pub fn reuse_generic_function_test() {
  let typer = init(fn(_) { todo })
  let scope = typer.root_scope([])
  let untyped =
    ast.let_(
      p.Variable("id"),
      ast.function(p.Tuple([Some("x")]), ast.variable("x")),
      ast.tuple_([
        ast.call(ast.variable("id"), ast.tuple_([])),
        ast.call(ast.variable("id"), ast.binary("")),
      ]),
    )
  let #(typed, typer) =
    infer(untyped, t.Tuple([t.Tuple([]), t.Binary]), #(typer, scope))
  let typer.Typer(substitutions: substitutions, ..) = typer
  let Ok(type_) = get_type(typed)
  let t.Tuple([t.Tuple([]), t.Binary]) = resolve(type_, substitutions)
}
//https://cs.stackexchange.com/questions/101152/let-rec-recursive-expression-static-typing-rule
//https://en.wikipedia.org/wiki/Hindley%E2%80%93Milner_type_system recursive definitions
//https://boxbase.org/entries/2018/mar/5/hindley-milner/
// https://medium.com/@dhruvrajvanshi/type-inference-for-beginners-part-2-f39c33ca9513
// https://ahnfelt.medium.com/type-inference-by-example-part-7-31e1d1d05f56
// it seems like not generalizing is important these tests make sense, hooray but there's still some weird recursive ness.
// https://www.cl.cam.ac.uk/teaching/1516/L28/type-inference.pdf
// pub fn recursive_type_test() {
//   let typer = init(fn(_) {todo})
// let scope = typer.root_scope([])
//   // let untyped = ast.let_(p.Variable("last"), last(), ast.variable("last"))
//   let untyped = ast.hole()
//   let #(typed, typer) = infer(untyped, t.Unbound(-1), #(typer, scope))
//   let typer.Typer(substitutions: substitutions, inconsistencies: i, ..) = typer
//   let [] = i
//   let Ok(type_) = get_type(typed)
//   let t.Function(t.Tuple([x, y]), z) = resolve(type_, substitutions)
//   let t.Function(t.Tuple([a, b]), c) = x
//   let typer =
//     init([
//       #(
//         "xs",
//         polytype.Polytype(
//           [999],
//           monotype.Function(
//             monotype.Tuple([
//               monotype.Function(monotype.Tuple([]), monotype.Unbound(999)),
//               monotype.Function(
//                 monotype.Tuple([monotype.Unbound(999), monotype.Unbound(1000)]),
//                 monotype.Unbound(999),
//               ),
//             ]),
//             monotype.Unbound(999),
//           ),
//         ),
//       ),
//     ])
//   let untyped =
//     ast.let_(
//       p.Variable("last"),
//       last(),
//       ast.call(
//         ast.variable("last"),
//         ast.tuple_([ast.variable("xs"), ast.binary("")]),
//       ),
//     )
//   let #(typed, typer) = infer(untyped, t.Unbound(-1), #(typer, scope))
//   let typer.Typer(substitutions: substitutions, inconsistencies: i, ..) = typer
//   let [] = i
//   let Ok(type_) = get_type(typed)
//   let t.Binary = resolve(type_, substitutions)
//   let untyped =
//     ast.let_(
//       p.Variable("last"),
//       last(),
//       ast.call(ast.variable("last"), ast.tuple_([empty(), ast.binary("")])),
//     )
//   let #(typed, typer) = infer(untyped, t.Unbound(-1), #(typer, scope))
//   let typer.Typer(substitutions: substitutions, inconsistencies: i, ..) = typer
//   let [] = i
//   let Ok(type_) = get_type(typed)
//   let t.Binary = resolve(type_, substitutions)
// }
// fn empty() {
//   ast.function(
//     p.Tuple([Some("then"), None]),
//     ast.call(ast.variable("then"), ast.tuple_([])),
//   )
// }
// fn one(next) {
//   ast.function(
//     p.Tuple([None, Some("then")]),
//     ast.call(ast.variable("then"), ast.tuple_([ast.binary("1"), next])),
//   )
// }
// pub fn num_equality_test() {
//   let typer = init([#("equal", typer.equal_fn())])
//   let untyped =
//     ast.call(
//       ast.variable("equal"),
//       ast.tuple_([one(one(one(one(empty())))), empty()]),
//     )
//   let #(typed, typer) = infer(untyped, t.Unbound(-1), #(typer, scope))
//   let typer.Typer(substitutions: substitutions, inconsistencies: i, ..) = typer
//   let [] = i
//   let #(_, e.Call(_, #(_, e.Tuple([l, r])))) = typed
//   let Ok(l_type) = get_type(l)
//   let Ok(r_type) = get_type(r)
//   let l_type = resolve(l_type, substitutions)
//   let r_type = resolve(r_type, substitutions)
//   io.debug(monotype.to_string(l_type))
//   let True = l_type == r_type
// }
