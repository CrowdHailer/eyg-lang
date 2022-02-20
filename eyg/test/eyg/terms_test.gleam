import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eyg
import eyg/ast
import eyg/ast/editor
import eyg/ast/expression.{
  binary, call, function, hole, let_, row, tuple_, variable,
}
import eyg/typer
import eyg/ast/expression as e
import eyg/typer/monotype as t
import eyg/ast/pattern as p
import eyg/typer/polytype
import eyg/inference

// builder pattern for adding variables in test where this would be helpful
// pub fn infer(untyped, type_) {
//   let native_to_string = fn(_: Nil) { "" }
//   let variables = [#("equal", typer.equal_fn())]
//   let checker = typer.init(native_to_string)
//   let scope = typer.root_scope(variables)
//   let state = #(checker, scope)
//   // TODO replace all variables
//   //
//   // sdo
//   typer.infer(untyped, type_, state)
// }
fn infer(untyped, type_) {
  inference.infer(untyped, type_)
}

fn unbound() {
  t.Unbound(-1)
}

fn get_type(typed, checker) {
  let #(typed, tree) = typed
  case typed {
    Ok(type_) -> {
      let resolved = inference.resolve(type_, checker)
      Ok(resolved)
    }
    Error(typer.UnmatchedTypes(expected, given)) -> {
      let expected = inference.resolve(expected, checker)
      let given = inference.resolve(given, checker)
      Error(typer.UnmatchedTypes(expected, given))
    }
    Error(reason) -> Error(reason)
  }
}

// TODO move to AST
fn get_expression(tree, path) {
  let editor.Expression(expression) = editor.get_element(tree, path)
  Ok(expression)
}

pub fn binary_expression_test() {
  let source = binary("Hello")
  let #(typed, checker) = infer(source, unbound())
  assert Ok(t.Binary) = get_type(typed, checker)

  let #(typed, checker) = infer(source, t.Binary)
  assert Ok(t.Binary) = get_type(typed, checker)

  let #(typed, checker) = infer(source, t.Tuple([]))
  assert Error(reason) = get_type(typed, checker)
  assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
}

pub fn tuple_expression_test() {
  let source = tuple_([binary("Hello")])
  let #(typed, checker) = infer(source, unbound())
  assert Ok(type_) = get_type(typed, checker)
  assert t.Tuple([t.Binary]) = type_
  let #(typed, checker) = infer(source, t.Tuple([unbound()]))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Tuple([t.Binary]) = type_
  let #(typed, checker) = infer(source, t.Tuple([t.Binary]))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Tuple([t.Binary]) = type_
  let #(typed, checker) = infer(source, t.Tuple([]))
  assert Error(reason) = get_type(typed, checker)
  assert typer.IncorrectArity(0, 1) = reason
  let #(typed, checker) = infer(source, t.Tuple([t.Tuple([])]))
  // Type is correct here only internally is there a failure
  assert Ok(t.Tuple([t.Tuple([])])) = get_type(typed, checker)
  assert Ok(element) = get_expression(typed, [0])
  assert Error(reason) = get_type(element, checker)
  assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
}

pub fn pair_test() {
  let source = tuple_([binary("Hello"), tuple_([])])
  let tx = t.Unbound(-1)
  let ty = t.Unbound(-2)
  let #(typed, checker) = infer(source, t.Tuple([tx, ty]))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Tuple([t.Binary, t.Tuple([])]) = type_
  // could check tx/ty bound properly
  let #(typed, checker) = infer(source, t.Tuple([tx, tx]))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Tuple([t.Binary, t.Binary]) = type_
  assert Ok(element) = get_expression(typed, [1])
  assert Error(reason) = get_type(element, checker)
  assert typer.UnmatchedTypes(t.Binary, t.Tuple([])) = reason
}

pub fn row_expression_test() {
  // TODO order when row is called
  let source = row([#("foo", binary("Hello"))])
  let #(typed, checker) = infer(source, unbound())
  assert Ok(type_) = get_type(typed, checker)
  assert t.Row([#("foo", t.Binary)], None) = type_
  let #(typed, checker) = infer(source, t.Row([#("foo", t.Binary)], None))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Row([#("foo", t.Binary)], None) = type_
  // TODO row with some
  let #(typed, checker) =
    infer(source, t.Row([#("foo", t.Binary), #("bar", t.Binary)], None))
  assert Error(reason) = get_type(typed, checker)
  assert typer.MissingFields([#("bar", t.Binary)]) = reason
  let #(typed, checker) = infer(source, t.Row([], None))
  assert Error(reason) = get_type(typed, checker)
  // assert typer.UnexpectedFields([#("foo", t.Binary)]) = reason
  // TODO move up
  let #(typed, checker) = infer(source, t.Row([#("foo", t.Tuple([]))], None))
  // TODO think which one I want most.
  // assert Ok(type_) = get_type(typed, checker)
  // assert t.Row([#("foo", t.Tuple([]))], None) = type_
  // assert Ok(element) = get_expression(typed, [0, 1])
  // assert Error(reason) = get_type(element, checker)
  // assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
  // ----- up to previous todo
  // T.Row(head, option(more_row))
  // Means no such thing as an empty record. Good because tuple is unit
  let #(typed, checker) = infer(source, t.Row([#("foo", t.Binary)], Some(-1)))
  assert Ok(type_) = get_type(typed, checker)
  // TODO should resolve to none
  // assert t.Row([#("foo", t.Binary)], None) = type_
}

// // TODO tag test
// // TODO patterns
pub fn var_expression_test() {
  let source = variable("x")
  let #(typed, checker) = infer(source, unbound())
  assert Error(reason) = get_type(typed, checker)
  // TODO check we're on the lowest unbound integer
  assert typer.UnknownVariable("x") = reason
}

// pub fn function_test() {
//   let source = function(p.Variable(""), binary(""))
//   let #(typed, checker) = infer(source, unbound())
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Function(t.Unbound(_), t.Binary) = type_
//   let #(typed, checker) = infer(source, t.Function(unbound(), t.Unbound(-2)))
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Function(t.Unbound(_), t.Binary) = type_
//   let #(typed, checker) = infer(source, t.Function(t.Tuple([]), t.Binary))
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Function(t.Tuple([]), t.Binary) = type_
//   let #(typed, checker) = infer(source, t.Function(unbound(), unbound()))
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Function(t.Binary, t.Binary) = type_
//   let #(typed, checker) = infer(source, t.Binary)
//   assert Error(reason) = get_type(typed, checker)
//   // assert typer.UnmatchedTypes(t.Binary, t.Function(t.Unbound(_), t.Tuple([]))) =
//   //   reason
//   // TODO move up
//   let #(typed, checker) = infer(source, t.Function(t.Tuple([]), t.Tuple([])))
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Function(t.Tuple([]), t.Tuple([])) = type_
//   assert Ok(body) = get_expression(typed, [1])
//   assert Error(reason) = get_type(body, checker)
//   assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
// }
// pub fn id_function_test() {
//   let source = function(p.Variable("x"), variable("x"))
//   let #(typed, checker) = infer(source, unbound())
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Function(t.Unbound(i), t.Unbound(j)) = type_
//   assert True = i == j
//   let #(typed, checker) = infer(source, t.Function(unbound(), t.Binary))
//   assert Ok(type_) = get_type(typed, checker)
//   // TODO check unbound is now binary
//   assert t.Function(t.Binary, t.Binary) = type_
//   let #(typed, checker) = infer(source, t.Function(t.Tuple([]), t.Binary))
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Function(t.Tuple([]), t.Binary) = type_
//   assert Ok(body) = get_expression(typed, [1])
//   assert Error(reason) = get_type(body, checker)
//   assert typer.UnmatchedTypes(t.Binary, t.Tuple([])) = reason
//   // Not this is saying that the variable is wrong some how
// }
// // equal bin bin
// // equal bin tuple still returns true
// pub fn call_function_test() {
//   let func = function(p.Tuple([]), binary(""))
//   let source = call(func, tuple_([]))
//   let #(typed, checker) = infer(source, unbound())
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Binary = type_
//   let #(typed, checker) = infer(source, t.Binary)
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Binary = type_
//   // Error is internal
//   // let #(typed, checker) = infer(source, t.Tuple([]))
//   // assert Error(reason) = get_type(typed, checker)
//   // assert typer.UnmatchedTypes(t.Tuple([]), t.Tuple([])) = reason
// }
// pub fn call_generic_function_test() {
//   let func = function(p.Variable("x"), variable("x"))
//   let source = call(func, tuple_([]))
//   let #(typed, checker) = infer(source, unbound())
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Tuple([]) = type_
//   let #(typed, checker) = infer(source, t.Tuple([]))
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Tuple([]) = type_
//   // error in generic pushed to arguments
//   let #(typed, checker) = infer(source, t.Binary)
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Binary = type_
//   assert Ok(body) = get_expression(typed, [1])
//   assert Error(reason) = get_type(body, checker)
//   assert typer.UnmatchedTypes(t.Binary, t.Tuple([])) = reason
// }
// pub fn call_not_a_function_test() {
//   let source = call(binary("no a func"), tuple_([]))
//   let #(typed, checker) = infer(source, t.Binary)
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Binary = type_
//   assert Ok(body) = get_expression(typed, [0])
//   assert Error(reason) = get_type(body, checker)
//   assert typer.UnmatchedTypes(expected, t.Binary) = reason
//   // TODO resolve expected
//   // assert t.Function(t.Tuple([]), t.Binary) = expected
// }
// pub fn hole_expression_test() {
//   let source = hole()
//   let #(typed, checker) = infer(source, unbound())
//   assert Ok(type_) = get_type(typed, checker)
//   // TODO check we're on the lowest unbound integer
//   assert t.Unbound(_) = type_
//   let #(typed, checker) = infer(source, t.Binary)
//   assert Ok(type_) = get_type(typed, checker)
//   assert t.Binary = type_
// }
// // patterns
// pub fn tuple_pattern_test() {
//   let source = function(p.Tuple(["x"]), variable("x"))
//   let #(typed, checker) = infer(source, unbound())
//   assert Ok(t.Function(from, _)) = get_type(typed, checker)
//   assert t.Tuple([t.Unbound(_)]) = from
//   let #(typed, checker) =
//     infer(source, t.Function(t.Tuple([unbound()]), t.Unbound(-2)))
//   assert Ok(t.Function(from, _)) = get_type(typed, checker)
//   assert t.Tuple([t.Unbound(_)]) = from
//   let #(typed, checker) =
//     infer(source, t.Function(t.Tuple([t.Binary]), t.Unbound(-2)))
//   assert Ok(t.Function(from, _)) = get_type(typed, checker)
//   assert t.Tuple([t.Binary]) = from
//   // wrong arity
//   let #(typed, checker) = infer(source, t.Function(t.Tuple([]), t.Unbound(-2)))
//   assert Error(reason) = get_type(typed, checker)
//   // TODO need to return the function error
//   assert typer.IncorrectArity(0, 1) = reason
//   // wrong bound type
//   let #(typed, checker) =
//     infer(source, t.Function(t.Tuple([t.Binary]), t.Tuple([])))
//   // Should this be an inside error or not
//   // assert Error(reason) = get_type(typed, checker)
//   // // TODO need to return the function error
//   // assert typer.UnmatchedTypes(t.Binary, t.Tuple([])) = reason
// }
// // let
// pub fn row_pattern_test() {
//   let source = function(p.Row([#("foo", "x")]), variable("x"))
//   // todo
// }
// // TODO expanding row type test
// // test reusing id
// // pub fn recursive_tuple_test() {
// //   let source =
// //     let_(
// //       p.Variable("f"),
// //       function(
// //         p.Tuple([]),
// //         tuple_([binary("x"), call(variable("f"), tuple_([]))]),
// //       ),
// //       variable("f"),
// //     )
// //   let #(typed, checker) = infer(source, unbound())
// //   assert Ok(t.Function(from, to)) = get_type(typed, checker)
// //   assert t.Tuple([]) = from
// //   // assert t.Tuple([t.Binary, t.Unbound(mu)]) = to
// //   // typer.get_type(typed)
// //   // |> io.debug
// //   list.map(checker.substitutions, io.debug)
// //   // io.debug(mu)
// //   // io.debug("----")
// //   let [x, .._] = checker.substitutions
// //   let #(-1, t.Function(_, t.Tuple(elements))) = x
// //   io.debug(elements)
// //   let [_, t.Recursive(mu, inner)] = elements
// //   io.debug("loow ")
// //   io.debug(mu)
// //   io.debug(inner)
// //   let t.Tuple([_, t.Unbound(x)]) = inner
// //   io.debug(x)
// // }
// fn my_infer(untyped, goal) {
//   do_my_infer(untyped, goal, [])
// }
// // Do this as alg J
// fn do_my_infer(untyped, goal, env) {
//   let #(_, untyped) = untyped
//   io.debug(untyped)
//   case untyped {
//     e.Let(p.Variable(f), #(_, e.Function(p.Variable(x), body)), then) -> {
//       let p = t.Unbound(1)
//       let r = t.Unbound(2)
//       let env = [#(f, t.Function(p, r)), #(x, p), ..env]
//       do_my_infer(body, r, env)
//     }
//     e.Tuple([e1, e2]) -> {
//       // unify goal tuple(tnext 1)
//       let t1 = t.Unbound(3)
//       let t2 = t.Unbound(4)
//       io.debug("goal")
//       io.debug(goal)
//       do_my_infer(e1, t1, env)
//       do_my_infer(e2, t2, env)
//     }
//     e.Binary(_) -> {
//       io.debug("is binary")
//       io.debug(goal)
//       #(1, 1)
//     }
//     e.Call(e1, e2) -> {
//       io.debug(goal)
//       io.debug(e1)
//       io.debug(e2)
//       // 0 = 1 -> 2
//       // 1 = Tuple([]) Null
//       // 2 = Tuple(3, 4)
//       // 3 = Binary
//       // 4 = 1 -> 2.1
//       // 2 = Tuple(Binary, 2)
//       // rA(Binary, A)
//       // rA[Nil | Cons (B, A)]
//       // reverse: rA[Nil | Cons (B, A)] -> rA[Nil | Cons (B, A)]
//       // map: rA[Nil | Cons (B, A)] -> (B, C) -> rD[Nil | Cons (C, D)]
//       // map: List(B) -> (B -> C) -> List(C)
//       todo("in call")
//     }
//     e.Variable(label) -> {
//       let t = list.key_find(env, label)
//       io.debug(t)
//       todo
//     }
//   }
//   // #(1, 1)
// }
pub fn recursive_loop_test() {
  let source =
    let_(
      p.Variable("f"),
      function(
        p.Variable("x"),
        let_(p.Variable("tmp"), binary(""), call(variable("f"), variable("x"))),
      ),
      variable("f"),
    )
  let #(typed, checker) = infer(source, unbound())
  assert Ok(t.Function(t.Unbound(i), t.Unbound(j))) = get_type(typed, checker)
  assert True = i != j
  // TODO x = i and f = i -> j internally but not poly
  // assert Ok(body) = get_expression(typed, [1])
  // assert Ok(t.Function(t.Unbound(i), t.Unbound(j))) = get_type(body, checker)
  // TODO ----
  // id called polymorphically internally FAil
  // id called polymorphically externally Success
}

// TODO let x = x Test
pub fn my_recursive_tuple_test() {
  let source =
    let_(
      p.Variable("f"),
      function(
        p.Variable("x"),
        tuple_([binary("hello"), call(variable("f"), tuple_([]))]),
      ),
      variable("f"),
    )
  let #(typed, checker) = infer(source, unbound())

  // io.debug("-=-------------------")
  // io.debug(typed)
  // list.map(
  //   checker.substitutions,
  //   fn(s) {
  //     let #(k, t) = s
  //     io.debug(k)
  //     // io.debug(t.to_string(t, fn(_) { "OOO" }))
  //     io.debug(inference.to_string(t, []))
  //   },
  // )
  let Ok(type_) = get_type(typed, checker)
  let "() -> μ0.(Binary, 0)" = inference.print(type_, checker)
  // inference.print(t.Unbound(4), checker)
  // |> io.debug
  // assert Ok(t.Function(from, to)) = get_type(typed, checker)
  // assert t.Tuple([]) = from
  // // assert t.Tuple([t.Binary, t.Unbound(mu)]) = to
  // // typer.get_type(typed)
  // // |> io.debug
  // list.map(checker.substitutions, io.debug)
  // // io.debug(mu)
  // // io.debug("----")
  // let [x, .._] = checker.substitutions
  // let #(-1, t.Function(_, t.Tuple(elements))) = x
  // io.debug(elements)
  // let [_, t.Recursive(mu, inner)] = elements
  // io.debug("loow ")
  // io.debug(mu)
  // io.debug(inner)
  // let t.Tuple([_, t.Unbound(x)]) = inner
  // io.debug(x)
}
