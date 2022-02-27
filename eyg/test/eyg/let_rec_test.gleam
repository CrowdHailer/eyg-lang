import gleam/io
import gleam/option.{None, Some}
import eyg
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer
import eyg/typer/monotype as t
import eyg/typer/polytype

fn infer(untyped, type_) {
  let native_to_string = fn(_: Nil) { "" }
  let variables = [#("equal", typer.equal_fn())]
  let checker = typer.init(native_to_string)
  let scope = typer.root_scope(variables)
  let state = #(checker, scope)
  typer.infer(untyped, type_, state)
}

fn get_type(typed, checker: typer.Typer(n)) {
  case typer.get_type(typed) {
    Ok(type_) -> Ok(t.resolve(type_, checker.substitutions))
    Error(reason) -> todo("resolve")
  }
}

// TODO let x = x Test
pub fn recursive_tuple_test() {
  let source =
    e.let_(
      p.Variable("f"),
      e.function(
        p.Variable("x"),
        e.tuple_([e.binary("hello"), e.call(e.variable("f"), e.tuple_([]))]),
      ),
      e.variable("f"),
    )
  let #(typed, checker) = infer(source, t.Unbound(-1))

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
  io.debug(checker.substitutions)
  assert Ok(type_) = get_type(typed, checker)
  let "() -> μ0.(Binary, 0)" =
    t.to_string(type_, fn(_) { todo("native") })
    |> io.debug
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
