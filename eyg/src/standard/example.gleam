import gleam/option.{Some}
import eyg/ast
import eyg/ast/pattern
import eyg/typer/monotype
import standard/builders.{clause}

pub fn boolean() {
  ast.row([
    #("Doc", ast.binary("Doc")),
    #(
      "True",
      ast.function(
        pattern.Row([#("True", "T")]),
        ast.call(ast.variable("T"), ast.tuple_([])),
      ),
    ),
    #(
      "False",
      ast.function(
        pattern.Row([#("False", "F")]),
        ast.call(ast.variable("F"), ast.tuple_([])),
      ),
    ),
    #(
      "and",
      ast.function(
        pattern.Tuple([Some("a"), Some("b")]),
        ast.call(
          ast.variable("a"),
          ast.row([
            #("True", ast.function(pattern.Tuple([]), ast.variable("b"))),
            #("False", ast.function(pattern.Tuple([]), ast.variable("False"))),
          ]),
        ),
      ),
    ),
  ])
}

pub fn simple() {
  ast.let_(
    pattern.Row([#("True", "True"), #("False", "False")]),
    boolean(),
    ast.let_(
      pattern.Variable("main"),
      ast.function(
        pattern.Tuple([]),
        ast.let_(
          pattern.Variable("a"),
          ast.tuple_([ast.binary("A"), ast.binary("B")]),
          ast.let_(
            pattern.Variable("b"),
            ast.binary("B"),
            ast.let_(
              pattern.Variable("c"),
              ast.row([#("foo", ast.binary("FOO"))]),
              ast.tuple_([ast.variable("a"), ast.variable("b")]),
            ),
          ),
        ),
      ),
      ast.call(ast.variable("main"), ast.tuple_([])),
    ),
  )
}
