import gleam/io
import gleam/list
import gleam/option.{None, Some}
import eyg
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer
import eyg/typer/monotype as t
import eyg/typer/polytype
import misc

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
    Ok(type_) -> {
      let type_ = t.resolve(type_, checker.substitutions)
      let used = t.used_in_type(type_)
      let #(minimal, _) =
        misc.map_state(used, 0, fn(used, i) { #(#(used, i), i + 1) })
      let type_ =
        list.fold(
          minimal,
          type_,
          fn(type_, replace) {
            let #(old, new) = replace
            polytype.replace_variable(type_, old, new)
          },
        )
      Ok(type_)
    }
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
  assert Ok(type_) = get_type(typed, checker)
  let "() -> μ0.(Binary, 0)" = t.to_string(type_, fn(_) { todo("native") })
}

pub fn recursive_union_test() {
  let source =
    e.let_(
      p.Variable("move"),
      e.function(
        p.Tuple(["from", "to"]),
        e.case_(
          e.variable("from"),
          [
            #("Nil", p.Tuple([]), e.variable("to")),
            #(
              "Cons",
              p.Tuple(["item", "rest"]),
              e.let_(
                p.Variable("from"),
                e.tagged(
                  "Cons",
                  e.tuple_([e.variable("item"), e.variable("to")]),
                ),
                e.call(
                  e.variable("move"),
                  e.tuple_([e.variable("rest"), e.variable("to")]),
                ),
              ),
            ),
          ],
        ),
      ),
      e.variable("move"),
    )
  io.debug("top")
  let #(typed, checker) = infer(source, t.Unbound(-1))
  io.debug("infered")
  assert Ok(type_) = get_type(typed, checker)
  let "() -> μ0.(Binary, 0)" =
    t.to_string(type_, fn(_) { todo("native") })
    |> io.debug
}

pub fn unification_test() {
  let typer = typer.init(fn(_) { "TODO" })
  assert Ok(typer) =
    typer.unify(t.Unbound(1), t.Tuple([t.Binary, t.Unbound(2)]), typer)
  assert Ok(typer) = typer.unify(t.Unbound(2), t.Unbound(1), typer)
  // io.debug("----------")
  // io.debug(typer.substitutions)
  // io.debug(t.resolve(t.Unbound(1), typer.substitutions))
  // io.debug(t.resolve(t.Unbound(2), typer.substitutions))
  // // TODO rest recursive
  // // TODO Should be the same type in base
  // todo
}
