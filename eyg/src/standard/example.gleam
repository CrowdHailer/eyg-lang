import eyg/ast
import eyg/ast/pattern
import eyg/typer/monotype
import standard/builders.{clause}

pub fn simple() {
  ast.let_(
    pattern.Variable("main"),
    ast.function(
      pattern.Tuple([]),
      ast.let_(
        pattern.Variable("a"),
        ast.binary("A"),
        ast.let_(
          pattern.Variable("b"),
          ast.binary("B"),
          ast.tuple_([ast.variable("a"), ast.variable("b")]),
        ),
      ),
    ),
    ast.call(ast.variable("main"), ast.tuple_([])),
  )
}

pub fn code() {
  ast.let_(
    pattern.Variable("main"),
    ast.binary("bob"),
    // ast.provider("", fn(_config, _type) { todo }),
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
            ast.function(
              pattern.Tuple(["left", "right"]),
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
