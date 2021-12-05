import gleam/option.{Some}
import eyg/ast
import eyg/ast/pattern
import eyg/typer/monotype
import standard/builders.{clause}

pub fn boolean() {
  ast.let_(
    pattern.Variable("True"),
    ast.function(
      pattern.Row([#("True", "then")]),
      ast.call(ast.variable("then"), ast.tuple_([])),
    ),
    ast.let_(
      pattern.Variable("False"),
      ast.function(
        pattern.Row([#("False", "then")]),
        ast.call(ast.variable("then"), ast.tuple_([])),
      ),
      ast.let_(
        pattern.Variable("and"),
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
        ast.row([
          #("Doc", ast.binary("Doc")),
          #("True", ast.variable("True")),
          #("False", ast.variable("False")),
          #("and", ast.variable("and")),
        ]),
      ),
    ),
  )
}

pub fn list() {
  ast.let_(
    pattern.Variable("Cons"),
    ast.function(
      pattern.Tuple([Some("head"), Some("tail")]),
      ast.function(
        pattern.Row([#("Cons", "then")]),
        ast.call(
          ast.variable("then"),
          ast.tuple_([ast.variable("head"), ast.variable("tail")]),
        ),
      ),
    ),
    ast.let_(
      pattern.Variable("Nil"),
      ast.function(
        pattern.Row([#("Nil", "then")]),
        ast.call(ast.variable("then"), ast.tuple_([])),
      ),
      ast.let_(
        pattern.Variable("reverse"),
        ast.function(
          pattern.Tuple([Some("remaining"), Some("accumulator")]),
          ast.call(
            ast.variable("remaining"),
            ast.row([
              #(
                "Cons",
                ast.function(
                  pattern.Tuple([Some("head"), Some("rest")]),
                  ast.call(
                    ast.variable("self"),
                    ast.tuple_([
                      ast.variable("rest"),
                      ast.call(
                        ast.variable("Cons"),
                        ast.tuple_([
                          ast.variable("head"),
                          ast.variable("accumulator"),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              #(
                "Nil",
                ast.function(pattern.Tuple([]), ast.variable("remaining")),
              ),
            ]),
          ),
        ),
        ast.row([]),
      ),
    ),
  )
}

pub fn minimal() {
  ast.let_(pattern.Variable("foo"), ast.binary("Hello"), ast.variable("foo"))
}

// TODO recursive type definition also need to reread about type being the same or contained within.
pub fn simple() {
  ast.let_(
    pattern.Variable("boolean"),
    boolean(),
    ast.let_(
      pattern.Variable("list"),
      list(),
      ast.let_(
        pattern.Variable("main"),
        ast.function(
          pattern.Tuple([]),
          ast.let_(
            pattern.Row([#("True", "t"), #("False", "f"), #("and", "&")]),
            ast.variable("boolean"),
            ast.let_(
              pattern.Variable("b"),
              ast.call(ast.variable("&"), ast.tuple_([])),
              // ast.tuple_([ast.variable("t"), ast.variable("t")]),
              ast.hole(),
            ),
          ),
        ),
        ast.call(ast.variable("main"), ast.tuple_([])),
      ),
    ),
  )
}
