import gleam/io
import gleam/int
import gleam/list
import gleam/string
import gleam/option.{None, Some}
import eyg
import eyg/analysis
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/editor/editor
import eyg/typer
import eyg/typer/monotype as t
import eyg/typer/polytype
import misc
import eyg/editor/type_info

fn infer(untyped, type_) {
  let variables = [#("equal", typer.equal_fn())]
  let checker = typer.init(fn(_){ todo("native to parameters in infer")})
  let scope = typer.root_scope(variables)
  let state = #(checker, scope)
  typer.infer(untyped, type_, state)
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
  assert Ok(type_) = analysis.get_type(typed, checker)
  let "() -> μ0.(Binary, 0)" =
    type_info.to_string(type_, fn(_) { todo("native") })
}

pub fn loop_test() {
  let source =
    e.let_(
      p.Variable("loop"),
      e.function(
        p.Variable("f"),
        e.case_(
          e.call(e.variable("f"), e.tuple_([])),
          [
            #("True", p.Tuple([]), e.call(e.variable("loop"), e.variable("f"))),
            #("False,", p.Tuple([]), e.binary("Done")),
          ],
        ),
      ),
      e.variable("loop"),
    )
  let #(typed, checker) = infer(source, t.Unbound(-1))
  assert Ok(type_) = analysis.get_type(typed, checker)
  let "() -> [True () | False, ()] -> Binary" =
    type_info.to_string(type_, fn(_) { todo("native") })
  // Shouldn't be getting stuck in case where return value is unknown
  // Needs a drop out
}

pub fn actor_loop_test()  {
  let source = e.let_(
    p.Variable("loop"),
    e.function(p.Variable("message"), e.variable("loop")),
    e.variable("loop")
  )
  let #(typed, checker) = infer(source, t.Unbound(-1))
  assert Ok(type_) = analysis.get_type(typed, checker)
  let "0 -> μ1.0 -> 1" =
    type_info.to_string(type_, fn(_) { todo("native") })
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
            #(
              "Cons",
              p.Tuple(["item", "rest"]),
              e.let_(
                p.Variable("to"),
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
            #("Nil", p.Tuple([]), e.variable("to")),
          ],
        ),
      ),
      e.let_(
        p.Variable("reverse"),
        e.function(
          p.Variable("items"),
          e.call(
            e.variable("move"),
            e.tuple_([e.variable("items"), e.tagged("Nil", e.tuple_([]))]),
          ),
        ),
        e.variable("reverse"),
      ),
    )

  let #(typed, checker) = infer(source, t.Unbound(-1))

  assert Ok(move_exp) = get_expression(typed, [1])
  assert Ok(type_) = analysis.get_type(move_exp, checker)
  assert "(μ0.[Cons (1, 0) | Nil ()], μ2.[Cons (1, 2) | Nil () | ..3]) -> μ2.[Cons (1, 2) | Nil () | ..3]" =
    type_info.to_string(type_, fn(_) { todo("native") })

  assert Ok(type_) = analysis.get_type(typed, checker)
  assert "μ0.[Cons (1, 0) | Nil ()] -> μ2.[Cons (1, 2) | Nil () | ..3]" =
    type_info.to_string(type_, fn(_) { todo("native") })
}

fn get_expression(tree, path) {
  assert editor.Expression(expression) = editor.get_element(tree, path)
  Ok(expression)
}
