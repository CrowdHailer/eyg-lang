import gleam/io
import gleam/list
import gleam/string
import gleam/option.{None, Some}
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer.{get_type, infer, init}
import eyg/typer/monotype as t
import eyg/typer/monotype.{resolve}
import eyg/typer/polytype.{State}
import eyg/codegen_test

fn empty() {
  ast.function(
    p.Tuple([Some("then"), None]),
    ast.call(ast.variable("then"), ast.tuple_([])),
  )
}

fn cons(head, tail) {
  ast.function(
    p.Tuple([None, Some("then")]),
    ast.call(ast.variable("then"), ast.tuple_([head, tail])),
  )
}

fn last() {
  ast.function(
    p.Tuple([Some("list"), Some("current")]),
    ast.call(
      ast.variable("list"),
      ast.tuple_([
        ast.function(p.Tuple([]), ast.variable("current")),
        ast.function(
          p.Tuple([Some("value"), Some("rest")]),
          ast.call(
            ast.variable("last"),
            ast.tuple_([ast.variable("rest"), ast.variable("value")]),
          ),
        ),
      ]),
    ),
  )
}

fn shift() {
  ast.function(
    p.Tuple([Some("a"), Some("b")]),
    ast.call(
      ast.variable("a"),
      ast.tuple_([
        ast.function(p.Tuple([]), ast.variable("b")),
        ast.function(
          p.Tuple([Some("value"), Some("rest")]),
          ast.call(
            ast.variable("shift"),
            ast.tuple_([
              ast.variable("rest"),
              cons(ast.variable("value"), ast.variable("b")),
            ]),
          ),
        ),
      ]),
    ),
  )
}

fn head_or() {
  ast.function(
    p.Tuple([Some("list"), Some("fallback")]),
    ast.call(
      ast.variable("list"),
      ast.tuple_([
        ast.function(p.Tuple([]), ast.variable("fallback")),
        ast.function(p.Tuple([Some("head"), None]), ast.variable("head")),
      ]),
    ),
  )
}

pub fn list_equality_test() {
  let typer = init([#("equal", typer.equal_fn())])
  let untyped = // ast.call(
    //   ast.variable("equal"),
    //   ast.tuple_([cons(ast.binary("A"), empty()), empty()]),
    // )
    ast.let_(
      p.Variable("shift"),
      shift(),
      ast.let_(
        p.Variable("both"),
        ast.call(
          ast.variable("shift"),
          ast.tuple_([
            cons(ast.binary("A"), empty()),
            cons(ast.binary("B"), empty()),
          ]),
        ),
        ast.call(
          head_or(),
          ast.tuple_([ast.variable("both"), ast.binary("sdf")]),
        ),
      ),
    )

  let #(typed, typer) = infer(untyped, t.Unbound(-1), typer)
  let State(substitutions: substitutions, inconsistencies: i, ..) = typer
  let [] = i
  let x = typed
  let Ok(t) = get_type(x)
  let t = resolve(t, substitutions)
  io.debug(substitutions)
  io.debug(monotype.to_string(t))
  let _ =
    codegen_test.compile(untyped, typer)
    |> string.join
    |> io.debug
  // let #(_, e.Call(_, #(_, e.Tuple([l, r])))) = typed
  // let Ok(l_type) = get_type(l)
  // let Ok(r_type) = get_type(r)
  // let r_type = resolve(r_type, substitutions)
  // io.debug(monotype.to_string(l_type))
  // let True = l_type == r_type
}
