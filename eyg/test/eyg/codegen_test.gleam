import gleam/io
import gleam/option.{None, Some}
import eyg/codegen/javascript
import eyg/ast
import eyg/ast/encode
import eyg/ast/pattern
import eyg/typer/monotype
import eyg/typer/polytype
import eyg/typer.{infer, init}

pub fn compile(untyped, scope) {
  let #(typed, typer) = infer(untyped, monotype.Unbound(-1), scope)
  javascript.render(typed, javascript.Generator(False, [], typer, None))
}

pub fn eval(untyped, scope) {
  let #(typed, typer) = infer(untyped, monotype.Unbound(-1), scope)
  javascript.eval(typed, typer)
}

pub fn variable_assignment_test() {
  let untyped =
    ast.let_(
      pattern.Variable("foo"),
      ast.binary("V1"),
      ast.let_(
        pattern.Variable("foo"),
        ast.variable("foo"),
        ast.variable("foo"),
      ),
    )
  let js = compile(untyped, #(init(), typer.root_scope([])))
  let [l1, l2, l3] = js
  let "let foo$1 = \"V1\";" = l1
  let "let foo$2 = foo$1;" = l2
  let "foo$2" = l3

  let "V1" = eval(untyped, #(init(), typer.root_scope([])))
}

fn with_equal(previous) {
  [
    #(
      "equal",
      polytype.Polytype(
        [1],
        monotype.Function(
          monotype.Tuple([monotype.Unbound(1), monotype.Unbound(1)]),
          // TODO really needs fixing
          monotype.Tuple([]),
        ),
      ),
    ),
    ..previous
  ]
}

pub fn nested_assignment_test() {
  let state = #(init(), typer.root_scope([]))
  let untyped =
    ast.let_(
      pattern.Variable("match"),
      ast.let_(pattern.Variable("tmp"), ast.binary("TMP!"), ast.variable("tmp")),
      ast.variable("match"),
    )
  let js = compile(untyped, state)
  let [l1, l2, l3, l4, l5] = js
  let "let match$1 = (() => {" = l1
  let "  let tmp$1 = \"TMP!\";" = l2
  let "  return tmp$1;" = l3
  let "})();" = l4
  let "match$1" = l5

  let "TMP!" = eval(untyped, #(init(), typer.root_scope([])))
}

pub fn tuple_term_test() {
  let untyped = ast.tuple_([ast.binary("abc"), ast.binary("xyz")])
  let js = compile(untyped, #(init(), typer.root_scope([])))
  let [l1] = js
  let "[\"abc\", \"xyz\"]" = l1

  let #("abc", "xyz") = eval(untyped, #(init(), typer.root_scope([])))
}

pub fn multiline_tuple_assignment_test() {
  let state = #(init(), typer.root_scope([]))
  let untyped =
    ast.tuple_([
      ast.let_(pattern.Variable("tmp"), ast.binary("TMP!"), ast.variable("tmp")),
      ast.binary("xyz"),
    ])
  let js = compile(untyped, state)
  let [l1, l2, l3, l4, l5, l6, l7] = js
  let "[" = l1
  let "  (() => {" = l2
  let "    let tmp$1 = \"TMP!\";" = l3
  let "    return tmp$1;" = l4
  let "  })()," = l5
  let "  \"xyz\"," = l6
  let "]" = l7

  let #("TMP!", "xyz") = eval(untyped, #(init(), typer.root_scope([])))
}

pub fn tuple_destructure_test() {
  let untyped =
    ast.let_(
      pattern.Tuple([Some("a"), Some("b")]),
      ast.tuple_([ast.binary("x"), ast.binary("y")]),
      ast.variable("a"),
    )
  let js = compile(untyped, #(init(), typer.root_scope([])))

  let [l1, l2] = js
  let "let [a$1, b$1] = [\"x\", \"y\"];" = l1
  let "a$1" = l2

  let "x" = eval(untyped, #(init(), typer.root_scope([])))
}

pub fn row_assignment_test() {
  let untyped =
    ast.row([
      #("first_name", ast.binary("Bob")),
      #("family_name", ast.binary("Ross")),
    ])
  let js = compile(untyped, #(init(), typer.root_scope([])))
  let [l1] = js
  let "{first_name: \"Bob\", family_name: \"Ross\"}" = l1

  let True =
    encode.object([
      #("first_name", encode.string("Bob")),
      #("family_name", encode.string("Ross")),
    ]) == eval(untyped, #(init(), typer.root_scope([])))
}

pub fn multiline_row_assignment_test() {
  let scope =
    typer.root_scope(
      []
      |> with_equal(),
    )
  let untyped =
    ast.row([
      #(
        "first_name",
        ast.let_(
          pattern.Variable("tmp"),
          ast.binary("TMP!"),
          ast.variable("tmp"),
        ),
      ),
      #("last_name", ast.binary("xyz")),
    ])
  let js = compile(untyped, #(init(), scope))
  let [l1, l2, l3, l4, l5, l6, l7] = js
  let "{" = l1
  let "  first_name: (() => {" = l2
  let "    let tmp$1 = \"TMP!\";" = l3
  let "    return tmp$1;" = l4
  let "  })()," = l5
  let "  last_name: \"xyz\"," = l6
  let "}" = l7

  let True =
    encode.object([
      #("first_name", encode.string("TMP!")),
      #("last_name", encode.string("xyz")),
    ]) == eval(untyped, #(init(), typer.root_scope([])))
}

pub fn row_destructure_test() {
  let untyped =
    ast.let_(
      pattern.Row([#("first_name", "a"), #("family_name", "b")]),
      ast.variable("user"),
      ast.tuple_([]),
    )
  let js =
    compile(
      untyped,
      #(
        init(),
        typer.root_scope([
          #("user", polytype.Polytype([], monotype.Unbound(-1))),
        ]),
      ),
    )
  let [l1, l2] = js
  let "let {first_name: a$1, family_name: b$1} = user;" = l1
  let "[]" = l2
}

pub fn simple_function_call_test() {
  let scope =
    typer.root_scope(
      []
      |> with_equal(),
    )
  let untyped =
    ast.call(
      ast.variable("equal"),
      ast.tuple_([ast.binary("foo"), ast.binary("bar")]),
    )
  let js = compile(untyped, #(init(), scope))
  let [l1] = js
  let "equal([\"foo\", \"bar\"])" = l1
}

pub fn oneline_function_test() {
  let state = #(init(), typer.root_scope([]))
  let untyped = ast.function(pattern.Tuple([Some("x")]), ast.variable("x"))
  let js = compile(untyped, state)
  let [l1] = js
  let "(function ([x$1]) { return x$1; })" = l1
}

pub fn call_oneline_function_test() {
  let state = #(init(), typer.root_scope([]))
  let untyped =
    ast.call(
      ast.function(pattern.Tuple([Some("x")]), ast.variable("x")),
      ast.tuple_([ast.binary("hello")]),
    )
  let js = compile(untyped, state)
  let [l1] = js
  let "(function ([x$1]) { return x$1; })([\"hello\"])" = l1

  let "hello" = eval(untyped, #(init(), typer.root_scope([])))
}

pub fn multiline_function_test() {
  let scope =
    typer.root_scope(
      []
      |> with_equal(),
    )
  let untyped =
    ast.function(
      pattern.Tuple([Some("a"), Some("b")]),
      ast.let_(
        pattern.Variable("a"),
        ast.call(
          ast.variable("equal"),
          ast.tuple_([ast.variable("a"), ast.binary("blah")]),
        ),
        ast.call(
          ast.variable("equal"),
          ast.tuple_([ast.variable("b"), ast.binary("other")]),
        ),
      ),
    )
  let state = #(init(), scope)
  let js = compile(untyped, state)
  let [l1, l2, l3, l4] = js
  let "(function ([a$1, b$1]) {" = l1
  let "  let a$2 = equal([a$1, \"blah\"]);" = l2
  let "  return equal([b$1, \"other\"]);" = l3
  let "})" = l4
}

pub fn multiline_call_function_test() {
  let state = #(init(), typer.root_scope([]))
  let untyped =
    ast.call(
      ast.function(pattern.Variable("x"), ast.variable("x")),
      ast.let_(
        pattern.Variable("tmp"),
        ast.binary("hello"),
        ast.variable("tmp"),
      ),
    )
  let js = compile(untyped, state)
  let [l1, l2, l3, l4] = js
  let "(function (x$1) { return x$1; })((() => {" = l1
  let "  let tmp$1 = \"hello\";" = l2
  let "  return tmp$1;" = l3
  let "})())" = l4

  let "hello" = eval(untyped, #(init(), typer.root_scope([])))
}
