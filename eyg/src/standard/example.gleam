import eyg/ast
import eyg/ast/pattern
import eyg/typer/monotype
import standard/builders.{clause, function}

pub fn code() {
  ast.let_(
    pattern.Variable("main"),
    ast.provider("", fn(_config, _type) { todo }),
    ast.name(
      #(
        "Boolean",
        #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
      ),
      ast.name(
        #(
          "Option",
          #(
            [1],
            [
              #("Some", monotype.Tuple([monotype.Unbound(1)])),
              #("None", monotype.Tuple([])),
            ],
          ),
        ),
        ast.let_(
          pattern.Variable("t"),
          ast.call(ast.constructor("Boolean", "True"), ast.tuple_([])),
          ast.let_(
            pattern.Variable("and"),
            function(
              ["left", "right"],
              ast.case_(
                "Boolean",
                ast.variable("left"),
                [
                  clause("True", [], ast.variable("right")),
                  clause(
                    "False",
                    [],
                    ast.call(
                      ast.constructor("Boolean", "False"),
                      ast.tuple_([]),
                    ),
                  ),
                ],
              ),
            ),
            ast.binary("banana"),
          ),
        ),
      ),
    ),
  )
}
