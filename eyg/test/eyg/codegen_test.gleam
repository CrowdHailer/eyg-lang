import gleam/io
import eyg/codegen/javascript
import eyg/ast
import eyg/ast/pattern
import eyg/typer.{infer, init}

fn compile(untyped, scope) {
  let Ok(_) = infer(untyped, scope)
  javascript.render(untyped, #(False, []))
}

external fn stringify(a) -> String =
  "" "JSON.stringify"

pub fn variable_assignment_test() {
  let untyped =
    ast.Let(
      pattern.Variable("foo"),
      ast.Binary("My First Value"),
      ast.Let(pattern.Variable("foo"), ast.Variable("foo"), ast.Variable("foo")),
    )
  let js = compile(untyped, init([]))
  let [l1, l2, l3] = js
  let "let foo$1 = \"My First Value\";" = l1
  let "let foo$2 = foo$1;" = l2
  let "foo$2" = l3
}
// pub fn nested_assignment_test() {
//   let scope =
//     init([])
//     |> scope.with_equal()
//   let untyped =
//     ast.Let(
//       "match",
//       ast.Let(
//         "tmp",
//         ast.Binary("TMP!"),
//         ast.Call(
//           ast.Variable("equal"),
//           [ast.Variable("tmp"), ast.Binary("test")],
//         ),
//       ),
//       ast.Variable("match"),
//     )
//   let js = compile(untyped, scope)
//   let [l1, l2, l3, l4, l5] = js
//   let "let match$1 = (() => {" = l1
//   let "  let tmp$1 = \"TMP!\";" = l2
//   let "  return equal$1(tmp$1, \"test\");" = l3
//   let "})();" = l4
//   let "match$1" = l5
// }
// pub fn let_destructure_test() {
//   let scope = init([])
//   let untyped =
//     varient(
//       "User",
//       [],
//       [constructor("User", [monotype.Binary()])],
//       destructure(
//         "User",
//         ["first_name"],
//         ast.Call(ast.Variable("User"), [ast.Binary("abc")]),
//         ast.Variable("first_name"),
//       ),
//     )
//   let js = compile(untyped, scope)
//   let [l1, l2, l3] = js
//   let "let User$1 = ((...args) => Object.assign({ type: \"User\" }, args));" =
//     l1
//   let "let [first_name$1] = Object.values(User$1(\"abc\"));" = l2
//   let "first_name$1" = l3
// }
// pub fn tuple_assignment_test() {
//   let untyped =
//     ast.Let(
//       pattern.Variable("pair"),
//       ast.Tuple([ast.Binary("abc"), ast.Binary("xyz")]),
//       ast.Variable("pair"),
//     )
//   let js = compile(untyped, init([]))
//   let [l1, l2] = js
//   let "let pair$1 = [\"abc\", \"xyz\"];" = l1
//   let "pair$1" = l2
// }
// pub fn nested_tuple_assignment_test() {
//   let scope =
//     init([])
//     |> scope.with_equal()
//   let untyped =
//     ast.Let(
//       "pair",
//       ast.Tuple([
//         ast.Let(
//           "tmp",
//           ast.Binary("TMP!"),
//           ast.Call(
//             ast.Variable("equal"),
//             [ast.Variable("tmp"), ast.Binary("test")],
//           ),
//         ),
//         ast.Binary("xyz"),
//       ]),
//       ast.Variable("pair"),
//     )
//   let js = compile(untyped, scope)
//   let [l1, l2, l3, l4, l5, l6, l7, l8] = js
//   let "let pair$1 = [" = l1
//   let "  (() => {" = l2
//   let "    let tmp$1 = \"TMP!\";" = l3
//   let "    return equal$1(tmp$1, \"test\");" = l4
//   let "  })()," = l5
//   let "  \"xyz\"," = l6
//   let "];" = l7
//   let "pair$1" = l8
// }
// pub fn tuple_destructure_test() {
//   let untyped =
//     function(
//       ["pair"],
//       destructure_tuple(["a", "b"], ast.Variable("pair"), ast.Variable("a")),
//     )
//   let js = compile(untyped, init([]))
//   let [l1, l2, l3, l4] = js
//   let "(function self(pair$1) {" = l1
//   let "  let [a$1, b$1] = pair$1;" = l2
//   let "  return a$1;" = l3
//   let "})" = l4
// }
// pub fn row_assignment_test() {
//   let untyped =
//     ast.Let(
//       "user",
//       row([
//         #("first_name", ast.Binary("Bob")),
//         #("family_name", ast.Binary("Ross")),
//       ]),
//       ast.Variable("user"),
//     )
//   let js = compile(untyped, init([]))
//   let [l1, l2] = js
//   let "let user$1 = {first_name: \"Bob\", family_name: \"Ross\"};" = l1
//   let "user$1" = l2
// }
// pub fn nested_row_assignment_test() {
//   let scope =
//     init([])
//     |> scope.with_equal()
//   let untyped =
//     row([
//       #(
//         "first_name",
//         ast.Let(
//           "tmp",
//           ast.Binary("TMP!"),
//           ast.Call(
//             ast.Variable("equal"),
//             [ast.Variable("tmp"), ast.Binary("test")],
//           ),
//         ),
//       ),
//       #("last_name", ast.Binary("xyz")),
//     ])
//   let js = compile(untyped, scope)
//   // io.print(javascript.concat(js))
//   let [l1, l2, l3, l4, l5, l6, l7] = js
//   let "{" = l1
//   let "  first_name: (() => {" = l2
//   let "    let tmp$1 = \"TMP!\";" = l3
//   let "    return equal$1(tmp$1, \"test\");" = l4
//   let "  })()," = l5
//   let "  last_name: \"xyz\"," = l6
//   let "}" = l7
// }
// pub fn row_destructure_test() {
//   let untyped =
//     function(
//       ["user"],
//       destructure_row(
//         [#("first_name", "a"), #("family_name", "b")],
//         ast.Variable("user"),
//         ast.Variable("a"),
//       ),
//     )
//   let js = compile(untyped, init([]))
//   let [l1, l2, l3, l4] = js
//   let "(function self(user$1) {" = l1
//   let "  let {first_name: a$1, family_name: b$1} = user$1;" = l2
//   let "  return a$1;" = l3
//   let "})" = l4
// }
// // Don't need to to a case expression for tuples
// pub fn case_with_boolean_test() {
//   let scope = init([])
//   let untyped =
//     support.with_boolean(function(
//       ["bool"],
//       case_(
//         ast.Variable("bool"),
//         [
//           clause("True", [], ast.Binary("hello")),
//           rest("ping", ast.Binary("bye!")),
//         ],
//       ),
//     ))
//   let js = compile(untyped, scope)
//   let [l1, l2, l3, l4, l5, l6, l7, l8, l9, l10, l11, l12] = js
//   let "let True$1 = ((...args) => Object.assign({ type: \"True\" }, args));" =
//     l1
//   let "let False$1 = ((...args) => Object.assign({ type: \"False\" }, args));" =
//     l2
//   let "(function self(bool$1) {" = l3
//   let "  return ((subject) => {" = l4
//   let "  if (subject.type == \"True\") {" = l5
//   let "    let [] = Object.values(subject);" = l6
//   let "    return \"hello\";" = l7
//   let "  } else {" = l8
//   let "    let ping$1 = subject;" = l9
//   let "    return \"bye!\";" = l10
//   let "  }})(bool$1);" = l11
//   let "})" = l12
// }
// pub fn case_with_multiline_subject_test() {
//   let scope =
//     init([])
//     |> scope.with_equal()
//   let untyped =
//     support.with_boolean(case_(
//       ast.Let(
//         pattern.Variable("x"),
//         ast.Binary("a"),
//         ast.Call(ast.Variable("equal"), [ast.Variable("x"), ast.Binary("b")]),
//       ),
//       [
//         clause("True", [], ast.Binary("hello")),
//         rest("ping", ast.Binary("bye!")),
//       ],
//     ))
//   let js = compile(untyped, scope)
//   let [l1, l2, l3, l4, l5, l6, l7, l8, l9, l10, l11, l12, l13] = js
//   let "let True$1 = ((...args) => Object.assign({ type: \"True\" }, args));" =
//     l1
//   let "let False$1 = ((...args) => Object.assign({ type: \"False\" }, args));" =
//     l2
//   let "((subject) => {" = l3
//   let "if (subject.type == \"True\") {" = l4
//   let "  let [] = Object.values(subject);" = l5
//   let "  return \"hello\";" = l6
//   let "} else {" = l7
//   let "  let ping$1 = subject;" = l8
//   let "  return \"bye!\";" = l9
//   let "}})((() => {" = l10
//   let "  let x$1 = \"a\";" = l11
//   let "  return equal$1(x$1, \"b\");" = l12
//   let "})())" = l13
// }
// pub fn simple_function_call_test() {
//   let scope =
//     init([])
//     |> scope.with_equal()
//   let untyped =
//     ast.Call(ast.Variable("equal"), [ast.Binary("foo"), ast.Binary("bar")])
//   let js = compile(untyped, scope)
//   let [l1] = js
//   let "equal$1(\"foo\", \"bar\")" = l1
// }
// pub fn oneline_function_test() {
//   let scope = init([])
//   let untyped =
//     ast.Let(
//       pattern.Variable("x"),
//       function(["x"], ast.Variable("x")),
//       ast.Variable("x"),
//     )
//   let js = compile(untyped, scope)
//   let [l1, l2] = js
//   let "let x$1 = (function self(x$1) { return x$1; });" = l1
//   let "x$1" = l2
// }
// pub fn call_oneline_function_test() {
//   let scope = init([])
//   let untyped =
//     ast.Call(function(["x"], ast.Variable("x")), [ast.Binary("hello")])
//   let js = compile(untyped, scope)
//   let [l1] = js
//   let "(function self(x$1) { return x$1; })(\"hello\")" = l1
// }
// pub fn multiline_function_test() {
//   let scope =
//     init([])
//     |> scope.with_equal()
//   let untyped =
//     ast.Let(
//       "test",
//       function(
//         ["a", "b"],
//         ast.Let(
//           "a",
//           ast.Call(
//             ast.Variable("equal"),
//             [ast.Variable("a"), ast.Binary("blah")],
//           ),
//           ast.Call(
//             ast.Variable("equal"),
//             [ast.Variable("b"), ast.Binary("other")],
//           ),
//         ),
//       ),
//       ast.Variable("test"),
//     )
//   let js = compile(untyped, scope)
//   let [l1, l2, l3, l4, l5] = js
//   let "let test$1 = (function self(a$1, b$1) {" = l1
//   let "  let a$2 = equal$1(a$1, \"blah\");" = l2
//   let "  return equal$1(b$1, \"other\");" = l3
//   let "});" = l4
//   let "test$1" = l5
// }
// pub fn multiline_call_function_test() {
//   let scope = init([])
//   let untyped =
//     ast.Call(
//       function(["x"], ast.Variable("x")),
//       [
//         ast.Let(
//           pattern.Variable("tmp"),
//           ast.Binary("hello"),
//           ast.Variable("tmp"),
//         ),
//       ],
//     )
//   let js = compile(untyped, scope)
//   let [l1, l2, l3, l4, l5, l6] = js
//   let "(function self(x$1) { return x$1; })(" = l1
//   let "  (() => {" = l2
//   let "    let tmp$1 = \"hello\";" = l3
//   let "    return tmp$1;" = l4
//   let "  })()," = l5
//   let ")" = l6
// }
// // TODO email to ask about other language front ends. Is there a long form place to ask discord program lang questions
// // program is going to render a call function that doesn't exist. 
