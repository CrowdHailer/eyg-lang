import gleam/io
import eyg/codegen/javascript
import eyg/ast
import eyg/ast/pattern
import eyg/typer/monotype
import eyg/typer/polytype
import eyg/typer.{infer, init}

fn compile(untyped, scope) {
  let #(typed, typer) = infer(untyped, monotype.Unbound(-1), scope)
  javascript.render(typed, #(False, [], typer))
}

pub fn variable_assignment_test() {
  let untyped =
    ast.let_(
      pattern.Variable("foo"),
      ast.binary("My First Value"),
      ast.let_(
        pattern.Variable("foo"),
        ast.variable("foo"),
        ast.variable("foo"),
      ),
    )
  let js = compile(untyped, init([]))
  let [l1, l2, l3] = js
  let "let foo$1 = \"My First Value\";" = l1
  let "let foo$2 = foo$1;" = l2
  let "foo$2" = l3
}

fn with_equal(previous) {
  [
    #(
      "equal",
      polytype.Polytype(
        [1],
        monotype.Function(
          monotype.Tuple([monotype.Unbound(1), monotype.Unbound(1)]),
          monotype.Nominal("Boolean", []),
        ),
      ),
    ),
    ..previous
  ]
}

pub fn nested_assignment_test() {
  let scope =
    init(
      []
      |> with_equal(),
    )
  let untyped =
    ast.let_(
      pattern.Variable("match"),
      ast.let_(
        pattern.Variable("tmp"),
        ast.binary("TMP!"),
        ast.call(
          ast.variable("equal"),
          ast.tuple_([ast.variable("tmp"), ast.binary("test")]),
        ),
      ),
      ast.variable("match"),
    )
  let js = compile(untyped, scope)
  let [l1, l2, l3, l4, l5] = js
  let "let match$1 = (() => {" = l1
  let "  let tmp$1 = \"TMP!\";" = l2
  let "  return equal(tmp$1, \"test\");" = l3
  let "})();" = l4
  let "match$1" = l5
}

pub fn tuple_term_test() {
  let untyped = ast.tuple_([ast.binary("abc"), ast.binary("xyz")])
  let js = compile(untyped, init([]))
  let [l1] = js
  let "[\"abc\", \"xyz\"]" = l1
}

pub fn multiline_tuple_assignment_test() {
  let scope =
    init(
      []
      |> with_equal(),
    )
  let untyped =
    ast.tuple_([
      ast.let_(
        pattern.Variable("tmp"),
        ast.binary("TMP!"),
        ast.call(
          ast.variable("equal"),
          ast.tuple_([ast.variable("tmp"), ast.binary("test")]),
        ),
      ),
      ast.binary("xyz"),
    ])
  let js = compile(untyped, scope)
  let [l1, l2, l3, l4, l5, l6, l7] = js
  let "[" = l1
  let "  (() => {" = l2
  let "    let tmp$1 = \"TMP!\";" = l3
  let "    return equal(tmp$1, \"test\");" = l4
  let "  })()," = l5
  let "  \"xyz\"," = l6
  let "]" = l7
}

pub fn tuple_destructure_test() {
  let untyped =
    ast.let_(pattern.Tuple(["a", "b"]), ast.variable("pair"), ast.tuple_([]))
  let js =
    compile(
      untyped,
      init([
        #(
          "pair",
          polytype.Polytype(
            [],
            monotype.Tuple([monotype.Binary, monotype.Binary]),
          ),
        ),
      ]),
    )
  let [l1, l2] = js
  let "let [a$1, b$1] = pair;" = l1
  let "[]" = l2
}

pub fn row_assignment_test() {
  let untyped =
    ast.row([
      #("first_name", ast.binary("Bob")),
      #("family_name", ast.binary("Ross")),
    ])
  let js = compile(untyped, init([]))
  let [l1] = js
  let "{first_name: \"Bob\", family_name: \"Ross\"}" = l1
}

pub fn multiline_row_assignment_test() {
  let scope =
    init(
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
          ast.call(
            ast.variable("equal"),
            ast.tuple_([ast.variable("tmp"), ast.binary("test")]),
          ),
        ),
      ),
      #("last_name", ast.binary("xyz")),
    ])
  let js = compile(untyped, scope)
  let [l1, l2, l3, l4, l5, l6, l7] = js
  let "{" = l1
  let "  first_name: (() => {" = l2
  let "    let tmp$1 = \"TMP!\";" = l3
  let "    return equal(tmp$1, \"test\");" = l4
  let "  })()," = l5
  let "  last_name: \"xyz\"," = l6
  let "}" = l7
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
      init([#("user", polytype.Polytype([], monotype.Unbound(-1)))]),
    )
  let [l1, l2] = js
  let "let {first_name: a$1, family_name: b$1} = user;" = l1
  let "[]" = l2
}

pub fn simple_function_call_test() {
  let scope =
    init(
      []
      |> with_equal(),
    )
  let untyped =
    ast.call(
      ast.variable("equal"),
      ast.tuple_([ast.binary("foo"), ast.binary("bar")]),
    )
  let js = compile(untyped, scope)
  let [l1] = js
  let "equal(\"foo\", \"bar\")" = l1
}

pub fn oneline_function_test() {
  let scope = init([])
  let untyped = ast.function(pattern.Tuple(["x"]), ast.variable("x"))
  let js = compile(untyped, scope)
  let [l1] = js
  let "(function self(x$1) { return x$1; })" = l1
}

pub fn call_oneline_function_test() {
  let scope = init([])
  let untyped =
    ast.call(
      ast.function(pattern.Tuple(["x"]), ast.variable("x")),
      ast.tuple_([ast.binary("hello")]),
    )
  let js = compile(untyped, scope)
  let [l1] = js
  let "(function self(x$1) { return x$1; })(\"hello\")" = l1
}

pub fn multiline_function_test() {
  let scope =
    init(
      []
      |> with_equal(),
    )
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
  let js = compile(untyped, scope)
  let [l1, l2, l3, l4] = js
  let "(function self(a$1, b$1) {" = l1
  let "  let a$2 = equal(a$1, \"blah\");" = l2
  let "  return equal(b$1, \"other\");" = l3
  let "})" = l4
}

pub fn multiline_call_function_test() {
  let scope = init([])
  let untyped =
    ast.call(
      ast.function(pattern.Tuple(["x"]), ast.variable("x")),
      ast.tuple_([
        ast.let_(
          pattern.Variable("tmp"),
          ast.binary("hello"),
          ast.variable("tmp"),
        ),
      ]),
    )
  let js = compile(untyped, scope)
  let [l1, l2, l3, l4, l5, l6] = js
  let "(function self(x$1) { return x$1; })(" = l1
  let "  (() => {" = l2
  let "    let tmp$1 = \"hello\";" = l3
  let "    return tmp$1;" = l4
  let "  })()," = l5
  let ")" = l6
}

// // TODO email to ask about other language front ends. Is there a long form place to ask discord program lang questions
// // program is going to render a call function that doesn't exist. 
pub fn nominal_term_test() {
  let scope = init([])
  let untyped =
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
      ast.call(
        ast.constructor("Option", "Some"),
        ast.tuple_([ast.binary("value")]),
      ),
    )
  let js = compile(untyped, scope)
  let [l1] = js
  let "(function (...inner) { return {variant: \"Some\", inner} })(\"value\")" =
    l1
}

// // Don't need multiline test as that is the same as multiline call
// // If we want to avoid immediatly invokin function then would need the test and a special case in codegen
pub fn case_with_boolean_test() {
  let scope =
    init([
      #(
        "x",
        polytype.Polytype([], monotype.Nominal("Option", [monotype.Binary])),
      ),
    ])
  let untyped =
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
      ast.case_(
        "Option",
        ast.variable("x"),
        [
          #(
            "Some",
            "$",
            ast.let_(
              pattern.Tuple(["value"]),
              ast.variable("$"),
              ast.variable("value"),
            ),
          ),
          #(
            "None",
            "$",
            ast.let_(pattern.Tuple([]), ast.variable("$"), ast.binary("other")),
          ),
        ],
      ),
    )
  let js = compile(untyped, scope)
  let [l1, l2, l3, l4, l5, l6] = js
  let "(({variant, inner: $}) => { switch (variant) {" = l1
  let "  case \"Some\": let [value$1] = $;" = l2
  let "    return value$1;" = l3
  let "  case \"None\": let [] = $;" = l4
  let "    return \"other\";" = l5
  let "}})(x)" = l6
}
