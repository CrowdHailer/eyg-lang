import eyg/ast
import eyg/ast/pattern
import eyg/typer/monotype
import standard/builders.{clause, function}

pub fn code() {
  ast.Let(pattern.Variable("main"), ast.Provider(999,fn(_type){todo}),
  ast.Name(
    #(
      "Boolean",
      #([], [#("True", monotype.Tuple([])), #("False", monotype.Tuple([]))]),
    ),
    ast.Name(
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
      ast.Let(
        pattern.Variable("t"),
        ast.Call(ast.Constructor("Boolean", "True"), ast.Tuple([])),
        ast.Let(
          pattern.Variable("and"),
          function(
            ["left", "right"],
            ast.Case(
              "Boolean",
              ast.Variable("left"),
              [
                clause("True", [], ast.Variable("right")),
                clause(
                  "False",
                  [],
                  ast.Call(ast.Constructor("Boolean", "False"), ast.Tuple([])),
                ),
              ],
            ),
          ),
          ast.Binary("banana"),
        ),
      ),
    ),
  ))
}

