// TODO move into codegen dir
import gleam/dynamic
import gleam/io
import gleam/option.{None, Some}
import eyg/codegen/javascript
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/encode
import eyg/ast/pattern
import eyg/typer/monotype as t
import eyg/typer/polytype
import eyg/typer
import platform/browser

pub fn compile(untyped, scope) {
  let #(typed, typer) = typer.infer(untyped, t.Unbound(-1), t.empty, scope)
  let #(typed, typer) = typer.expand_providers(typed, typer, [])
  javascript.render(typed, javascript.Generator(False, [], typer, None))
}

pub fn eval(untyped, scope) {
  let #(typed, typer) = typer.infer(untyped, t.Unbound(-1), t.empty, scope)
  let #(typed, typer) = typer.expand_providers(typed, typer, [])
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
  let js = compile(untyped, #(typer.init(), typer.root_scope([])))
  let [l1, l2, l3] = js
  let "let foo$1 = \"V1\";" = l1
  let "let foo$2 = foo$1;" = l2
  let "foo$2" = l3
  assert True =
    dynamic.from("V1") == eval(untyped, #(typer.init(), typer.root_scope([])))
}

pub fn nested_assignment_test() {
  let state = #(typer.init(), typer.root_scope([]))
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
  assert True =
    dynamic.from("TMP!") == eval(untyped, #(typer.init(), typer.root_scope([])))
}

pub fn tuple_term_test() {
  let untyped = ast.tuple_([ast.binary("abc"), ast.binary("xyz")])
  let js = compile(untyped, #(typer.init(), typer.root_scope([])))
  let [l1] = js
  let "[\"abc\", \"xyz\"]" = l1
  assert True =
    dynamic.from(#("abc", "xyz")) == eval(
      untyped,
      #(typer.init(), typer.root_scope([])),
    )
}

pub fn multiline_tuple_assignment_test() {
  let state = #(typer.init(), typer.root_scope([]))
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
  assert True =
    dynamic.from(#("TMP!", "xyz")) == eval(
      untyped,
      #(typer.init(), typer.root_scope([])),
    )
}

pub fn tuple_destructure_test() {
  let untyped =
    ast.let_(
      pattern.Tuple(["a", "b"]),
      ast.tuple_([ast.binary("x"), ast.binary("y")]),
      ast.variable("a"),
    )
  let js = compile(untyped, #(typer.init(), typer.root_scope([])))

  let [l1, l2] = js
  let "let [a$1, b$1] = [\"x\", \"y\"];" = l1
  let "a$1" = l2
  assert True =
    dynamic.from("x") == eval(untyped, #(typer.init(), typer.root_scope([])))
}

pub fn record_assignment_test() {
  let untyped =
    e.record([
      #("first_name", ast.binary("Bob")),
      #("family_name", ast.binary("Ross")),
    ])
  let js = compile(untyped, #(typer.init(), typer.root_scope([])))
  let [l1] = js
  let "{first_name: \"Bob\", family_name: \"Ross\"}" = l1

  assert True =
    dynamic.from(encode.object([
      #("first_name", encode.string("Bob")),
      #("family_name", encode.string("Ross")),
    ])) == eval(untyped, #(typer.init(), typer.root_scope([])))
}

pub fn multiline_record_assignment_test() {
  let scope = typer.root_scope([])
  let untyped =
    e.record([
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
  let js = compile(untyped, #(typer.init(), scope))
  let [l1, l2, l3, l4, l5, l6, l7] = js
  let "{" = l1
  let "  first_name: (() => {" = l2
  let "    let tmp$1 = \"TMP!\";" = l3
  let "    return tmp$1;" = l4
  let "  })()," = l5
  let "  last_name: \"xyz\"," = l6
  let "}" = l7

  assert True =
    dynamic.from(encode.object([
      #("first_name", encode.string("TMP!")),
      #("last_name", encode.string("xyz")),
    ])) == eval(untyped, #(typer.init(), typer.root_scope([])))
}

pub fn record_destructure_test() {
  let untyped =
    ast.let_(
      pattern.Record([#("first_name", "a"), #("family_name", "b")]),
      ast.variable("user"),
      ast.tuple_([]),
    )
  let js =
    compile(
      untyped,
      #(
        typer.init(),
        typer.root_scope([#("user", polytype.Polytype([], t.Unbound(-1)))]),
      ),
    )
  let [l1, l2] = js
  let "let {first_name: a$1, family_name: b$1} = user;" = l1
  let "[]" = l2
}

// TODO use json lib
pub fn tagged_assignment_test() {
  let untyped = e.tagged("Some", ast.binary("Sue"))
  let js = compile(untyped, #(typer.init(), typer.root_scope([])))

  let [l1] = js
  let "{Some: \"Sue\"}" = l1

  assert True =
    dynamic.from(encode.object([#("Some", encode.string("Sue"))])) == eval(
      untyped,
      #(typer.init(), typer.root_scope([])),
    )
}

pub fn multiline_tagged_assignment_test() {
  let scope = typer.root_scope([])
  let untyped =
    e.tagged(
      "Some",
      ast.let_(pattern.Variable("tmp"), ast.binary("TMP!"), ast.variable("tmp")),
    )

  let js = compile(untyped, #(typer.init(), scope))
  let [l1, l2, l3, l4, l5, l6] = js
  let "{Some:" = l1
  let "  (() => {" = l2
  let "    let tmp$1 = \"TMP!\";" = l3
  let "    return tmp$1;" = l4
  let "  })()" = l5
  let "}" = l6

  assert True =
    dynamic.from(encode.object([#("Some", encode.string("TMP!"))])) == eval(
      untyped,
      #(typer.init(), typer.root_scope([])),
    )
}

pub fn simple_function_call_test() {
  let scope = typer.root_scope([#("equal", typer.equal_fn())])
  let untyped =
    ast.call(
      ast.variable("equal"),
      ast.tuple_([ast.binary("foo"), ast.binary("bar")]),
    )
  let js = compile(untyped, #(typer.init(), scope))
  let [l1] = js
  let "equal([\"foo\", \"bar\"])" = l1
}

pub fn oneline_function_test() {
  let state = #(typer.init(), typer.root_scope([]))
  let untyped = ast.function(pattern.Tuple(["x"]), ast.variable("x"))
  let js = compile(untyped, state)
  let [l1] = js
  let "(function ([x$1]) { return x$1; })" = l1
}

pub fn call_oneline_function_test() {
  let state = #(typer.init(), typer.root_scope([]))
  let untyped =
    ast.call(
      ast.function(pattern.Tuple(["x"]), ast.variable("x")),
      ast.tuple_([ast.binary("hello")]),
    )
  let js = compile(untyped, state)
  let [l1] = js
  let "(function ([x$1]) { return x$1; })([\"hello\"])" = l1

  assert True =
    dynamic.from("hello") == eval(
      untyped,
      #(typer.init(), typer.root_scope([])),
    )
}

pub fn multiline_function_test() {
  let scope = typer.root_scope([#("equal", typer.equal_fn())])
  let untyped =
    ast.function(
      pattern.Tuple(["a", "b"]),
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
  let state = #(typer.init(), scope)
  let js = compile(untyped, state)
  let [l1, l2, l3, l4] = js
  let "(function ([a$1, b$1]) {" = l1
  let "  let a$2 = equal([a$1, \"blah\"]);" = l2
  let "  return equal([b$1, \"other\"]);" = l3
  let "})" = l4
}

pub fn multiline_call_function_test() {
  let state = #(typer.init(), typer.root_scope([]))
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

  assert True =
    dynamic.from("hello") == eval(
      untyped,
      #(typer.init(), typer.root_scope([])),
    )
}
