import gleam/io
import eyg
import eyg/ast
import eyg/ast/pattern as p
import eyg/typer
import eyg/typer/monotype as t
import platform/browser

fn assigned(tree) {
  ast.let_(p.Variable("foo"), tree, ast.variable("foo"))
}

fn compile(source) {
  let #(typed, typer) = eyg.compile_unconstrained(source, browser.harness())
  assert [] = typer.inconsistencies
  let typer.Typer(substitutions: substitutions, ..) = typer
  assert Ok(type_) = typer.get_type(typed)
  t.resolve(type_, substitutions)
}

pub fn function_with_concrete_type_test() {
  let source = assigned(ast.function(p.Tuple([]), ast.binary("")))
  assert t.Function(t.Tuple([]), t.Binary) = compile(source)
}

pub fn identity_function_test() {
  let source = assigned(ast.function(p.Variable("x"), ast.variable("x")))
  assert t.Function(t.Unbound(i), t.Unbound(j)) = compile(source)
  assert True = i == j
}

pub fn external_variable_binding_test() {
  let source =
    ast.function(
      p.Variable("a"),
      ast.let_(
        p.Variable("f"),
        ast.function(p.Tuple([]), ast.variable("a")),
        ast.let_(p.Tuple([]), ast.variable("a"), ast.variable("f")),
      ),
    )
  assert t.Function(t.Tuple([]), t.Function(t.Tuple([]), t.Tuple([]))) =
    compile(source)
}

pub fn recursive_test() {
  let source = last()
  // assigned(ast.function(
  //   p.Tuple([None, Some("a")]),
  //   ast.call(ast.variable("foo"), ast.variable("a")),
  // ))
  assert t.Function(t.Tuple([]), t.Function(t.Tuple([]), t.Tuple([]))) =
    compile(source)
}

fn last() {
  ast.let_(
    p.Variable("last"),
    ast.function(
      p.Variable("xs"),
      ast.case_(
        ast.variable("xs"),
        [
          #(
            "Cons",
            p.Tuple(["", "rest"]),
            ast.call(ast.variable("last"), ast.variable("rest")),
          ),
          #("Nil", p.Tuple([]), ast.binary("")),
        ],
      ),
    ),
    ast.variable("last"),
  )
}
