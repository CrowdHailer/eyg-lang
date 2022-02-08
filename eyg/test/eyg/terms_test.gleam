import gleam/io
import gleam/option.{None, Some}
import eyg
import eyg/ast
import eyg/ast/editor
import eyg/ast/expression.{binary, call, function, hole, row, tuple_, variable}
import eyg/typer
import eyg/typer/monotype as t
import eyg/ast/pattern as p
import eyg/typer/polytype

// builder pattern for adding variables in test where this would be helpful
pub fn infer(untyped, type_) {
  let native_to_string = fn(_: Nil) { "" }
  let variables = [#("equal", typer.equal_fn())]
  let checker = typer.init(native_to_string)
  let scope = typer.root_scope(variables)
  let state = #(checker, scope)
  // TODO replace all variables
  //
  // sdo
  typer.infer(untyped, type_, state)
}

fn unbound() {
  t.Unbound(-1)
}

fn get_type(typed, checker: typer.Typer(a)) {
  try type_ = typer.get_type(typed)
  let resolved = t.resolve(type_, checker.substitutions)
  Ok(resolved)
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

// TODO merge hole
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

  // TODO resolve types in errors too
  // assert typer.UnexpectedFields([#("foo", t.Binary)]) = reason
  let #(typed, checker) = infer(source, t.Row([#("foo", t.Tuple([]))], None))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Row([#("foo", t.Tuple([]))], None) = type_
  assert Ok(element) = get_expression(typed, [0, 1])
  assert Error(reason) = get_type(element, checker)
  assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason

  // T.Row(head, option(more_row))
  // Means no such thing as an empty record. Good because tuple is unit
  let #(typed, checker) = infer(source, t.Row([#("foo", t.Binary)], Some(-1)))
  assert Ok(type_) = get_type(typed, checker)
  // TODO should resolve to none
  // assert t.Row([#("foo", t.Binary)], None) = type_
}

// TODO tag test
// TODO patterns
pub fn var_expression_test() {
  let source = variable("x")

  let #(typed, checker) = infer(source, unbound())
  assert Error(reason) = get_type(typed, checker)
  // TODO check we're on the lowest unbound integer
  assert typer.UnknownVariable("x") = reason
}

pub fn function_test() {
  let source = function(p.Variable(""), binary(""))

  let #(typed, checker) = infer(source, unbound())
  assert Ok(type_) = get_type(typed, checker)
  assert t.Function(t.Unbound(_), t.Binary) = type_

  let #(typed, checker) = infer(source, t.Function(unbound(), t.Unbound(-2)))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Function(t.Unbound(_), t.Binary) = type_

  let #(typed, checker) = infer(source, t.Function(t.Tuple([]), t.Binary))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Function(t.Tuple([]), t.Binary) = type_

  let #(typed, checker) = infer(source, t.Function(unbound(), unbound()))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Function(t.Binary, t.Binary) = type_

  let #(typed, checker) = infer(source, t.Binary)
  assert Error(reason) = get_type(typed, checker)

  // TODO resolve errors
  // assert typer.UnmatchedTypes(t.Binary, t.Function(t.Unbound(_), t.Tuple([]))) =
  //   reason
  let #(typed, checker) = infer(source, t.Function(t.Tuple([]), t.Tuple([])))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Function(t.Tuple([]), t.Tuple([])) = type_
  assert Ok(body) = get_expression(typed, [1])
  assert Error(reason) = get_type(body, checker)
  assert typer.UnmatchedTypes(t.Tuple([]), t.Binary) = reason
}

pub fn id_function_test() {
  let source = function(p.Variable("x"), variable("x"))

  let #(typed, checker) = infer(source, unbound())
  assert Ok(type_) = get_type(typed, checker)
  assert t.Function(t.Unbound(i), t.Unbound(j)) = type_
  assert True = i == j

  let #(typed, checker) = infer(source, t.Function(unbound(), t.Binary))
  assert Ok(type_) = get_type(typed, checker)
  // TODO check unbound is now binary
  assert t.Function(t.Binary, t.Binary) = type_

  let #(typed, checker) = infer(source, t.Function(t.Tuple([]), t.Binary))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Function(t.Tuple([]), t.Binary) = type_
  assert Ok(body) = get_expression(typed, [1])
  assert Error(reason) = get_type(body, checker)
  assert typer.UnmatchedTypes(t.Binary, t.Tuple([])) = reason
  // Not this is saying that the variable is wrong some how
}

// equal bin bin
// equal bin tuple still returns true
pub fn call_function_test() {
  let func = function(p.Tuple([]), binary(""))
  let source = call(func, tuple_([]))

  let #(typed, checker) = infer(source, unbound())
  assert Ok(type_) = get_type(typed, checker)
  assert t.Binary = type_

  let #(typed, checker) = infer(source, t.Binary)
  assert Ok(type_) = get_type(typed, checker)
  assert t.Binary = type_
  // Error is internal
  // let #(typed, checker) = infer(source, t.Tuple([]))
  // assert Error(reason) = get_type(typed, checker)
  // assert typer.UnmatchedTypes(t.Tuple([]), t.Tuple([])) = reason
}

pub fn call_generic_function_test() {
  let func = function(p.Variable("x"), variable("x"))
  let source = call(func, tuple_([]))

  let #(typed, checker) = infer(source, unbound())
  assert Ok(type_) = get_type(typed, checker)
  assert t.Tuple([]) = type_

  let #(typed, checker) = infer(source, t.Tuple([]))
  assert Ok(type_) = get_type(typed, checker)
  assert t.Tuple([]) = type_

  // error in generic pushed to arguments
  let #(typed, checker) = infer(source, t.Binary)
  assert Ok(type_) = get_type(typed, checker)
  assert t.Binary = type_
  assert Ok(body) = get_expression(typed, [1])
  assert Error(reason) = get_type(body, checker)
  assert typer.UnmatchedTypes(t.Binary, t.Tuple([])) = reason
}

pub fn call_not_a_function_test() {
  let source = call(binary("no a func"), tuple_([]))

  let #(typed, checker) = infer(source, t.Binary)
  assert Ok(type_) = get_type(typed, checker)
  assert t.Binary = type_
  assert Ok(body) = get_expression(typed, [0])
  assert Error(reason) = get_type(body, checker)
  assert typer.UnmatchedTypes(expected, t.Binary) = reason
  // TODO resolve expected
  // assert t.Function(t.Tuple([]), t.Binary) = expected
}

pub fn hole_expression_test() {
  let source = hole()

  let #(typed, checker) = infer(source, unbound())
  assert Ok(type_) = get_type(typed, checker)
  // TODO check we're on the lowest unbound integer
  assert t.Unbound(_) = type_

  let #(typed, checker) = infer(source, t.Binary)
  assert Ok(type_) = get_type(typed, checker)
  assert t.Binary = type_
}
