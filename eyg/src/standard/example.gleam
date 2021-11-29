import gleam/option.{Some}
import eyg/ast
import eyg/ast/pattern
import eyg/typer/monotype
import standard/builders.{clause}

pub fn boolean() {
  ast.call(
    ast.function(
      pattern.Tuple([]),
      ast.let_(
        pattern.Variable("True"),
        ast.function(
          pattern.Row([#("True", "T")]),
          ast.call(ast.variable("T"), ast.tuple_([])),
        ),
        ast.let_(
          pattern.Variable("False"),
          ast.function(
            pattern.Row([#("False", "F")]),
            ast.call(ast.variable("F"), ast.tuple_([])),
          ),
          ast.let_(
            pattern.Variable("and"),
            ast.function(
              pattern.Tuple([Some("a"), Some("b")]),
              ast.call(
                ast.variable("a"),
                ast.row([
                  #("True", ast.function(pattern.Tuple([]), ast.variable("b"))),
                  #(
                    "False",
                    ast.function(pattern.Tuple([]), ast.variable("False")),
                  ),
                ]),
              ),
            ),
            ast.row([
              #("Doc", ast.binary("Doc")),
              #("True", ast.variable("True")),
              #("False", ast.variable("False")),
              #("and", ast.variable("and")),
            ]),
          ),
        ),
      ),
    ),
    ast.tuple_([]),
  )
}

pub fn simple() {
  ast.let_(
    pattern.Variable("boolean"),
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
