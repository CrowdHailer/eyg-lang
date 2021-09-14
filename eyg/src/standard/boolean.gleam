import eyg/ast
import eyg/ast/pattern
import eyg/typer/monotype
import standard/builders.{clause}

pub fn code() {
  ast.name(
    #(
      "Boolean",
      #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
    ),
    ast.let_(
      pattern.Variable("True"),
      ast.call(ast.constructor("Boolean", "True"), ast.tuple_([])),
      ast.let_(
        pattern.Variable("False"),
        ast.call(ast.constructor("Boolean", "False"), ast.tuple_([])),
        ast.row([
          #("True", ast.variable("True")),
          #("False", ast.variable("False")),
          #(
            "and",
            ast.function(
              pattern.Tuple(["left", "right"]),
              ast.case_(
                "Boolean",
                ast.variable("left"),
                [
                  clause("True", [], ast.variable("right")),
                  clause("False", [], ast.variable("False")),
                ],
              ),
            ),
          ),
          #(
            "or",
            ast.function(
              pattern.Tuple(["left", "right"]),
              ast.case_(
                "Boolean",
                ast.variable("left"),
                [
                  clause("True", [], ast.variable("True")),
                  clause("False", [], ast.variable("right")),
                ],
              ),
            ),
          ),
        ]),
      ),
    ),
  )
}

pub fn test() {
  ast.let_(
    pattern.Row([
      #("and", "and"),
      #("or", "or"),
      #("True", "True"),
      #("False", "False"),
    ]),
    ast.variable("boolean"),
    ast.let_(
      pattern.Variable("should$equal"),
      ast.function(
        pattern.Tuple(["given", "expected"]),
        ast.case_(
          "Boolean",
          ast.call(
            ast.variable("equal"),
            ast.tuple_([ast.variable("given"), ast.variable("expected")]),
          ),
          [
            clause("True", [], ast.tuple_([])),
            clause(
              "False",
              [],
              ast.call(
                ast.variable("hole"),
                ast.tuple_([ast.binary("Should equal")]),
              ),
            ),
          ],
        ),
      ),
      ast.call(
        ast.variable("should$equal"),
        ast.tuple_([
          ast.variable("True"),
          ast.call(
            ast.variable("and"),
            ast.tuple_([ast.variable("True"), ast.variable("True")]),
          ),
        ]),
      ),
    ),
  )
}
