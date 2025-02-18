import eyg/compile
import eyg/parse
import gleam/dict
import gleam/dynamic
import gleam/dynamicx
import gleam/json
import gleam/pair
import gleeunit/should
import plinth/browser/window

fn test_compilation(source, js, evaled) {
  let generated =
    source
    |> parse.from_string()
    |> should.be_ok()
    |> pair.first()
    |> compile.to_js(dict.new())
  generated
  |> should.equal(js)
  generated
  |> window.eval()
  |> should.be_ok()
  |> should.equal(dynamic.from(evaled))
}

fn test_eval(source, evaled) {
  let generated =
    source
    |> parse.from_string()
    |> should.be_ok()
    |> pair.first()
    |> compile.to_js(dict.new())
  generated
  |> window.eval()
  |> should.be_ok()
  |> should.equal(dynamic.from(evaled))
}

pub fn literal_test() {
  test_compilation(
    "let num = 5
    num",
    "let num$0 = 5;
num$0",
    5,
  )

  test_compilation(
    "let str = \"hello\"
    str",
    "let str$0 = \"hello\";
str$0",
    "hello",
  )
}

pub fn let_assignment_test() {
  test_compilation(
    "let a = 1
    let b = 2
    b",
    "let a$0 = 1;
let b$2 = 2;
b$2",
    2,
  )
  // nesting is lifted
  test_compilation(
    "let a =
      let b = 80
      b
    a",
    "let b$1 = 80;
let a$0 = b$1;
a$0",
    80,
  )
  // shadowing
  test_compilation(
    "let x = 1
    let x = 2
    x",
    "let x$0 = 1;
let x$2 = 2;
x$2",
    2,
  )
}

pub fn iife_test() {
  test_compilation("(x) -> { x }(2)", "((x$1) => {\n  return x$1;\n})(2)", 2)
  test_compilation(
    "(x, y) -> { y }(2, 7)",
    // literals dont need curl and return for body useful for multiarity fns
    "((x$2) => {\n  return ((y$3) => {\n  return y$3;\n});\n})(2)(7)",
    7,
  )
}

pub fn list_test() {
  test_compilation("[1, 2]", "[1, [2, []]]", #(1, #(2, #())))
  test_compilation(
    "let x = [3, 2]
    x",
    "let x$0 = [3, [2, []]];
x$0",
    #(3, #(2, #())),
  )
  test_compilation(
    "[(x) -> { x }(1), 2]",
    "[((x$4) => {\n  return x$4;\n})(1), [2, []]]",
    #(1, #(2, #())),
  )
  test_compilation(
    "[let y = 5 y]",
    "let y$3 = 5;
[y$3, []]",
    #(5, #()),
  )
}

pub fn record_test() {
  test_compilation("{}", "({})", json.object([]))
  test_compilation("{a: 4}.a", "({a: 4}).a", 4)
  test_compilation(
    "let rec = {a: 1, b: 7}
    rec.a",
    "let rec$0 = ({a: 1, b: 7});\nrec$0.a",
    1,
  )
  test_compilation(
    "let rec = {a: 1, b: 7}
    rec.b",
    "let rec$0 = ({a: 1, b: 7});\nrec$0.b",
    7,
  )
  test_compilation(
    "let rec = {a: 1, b: {x: 5}}
    rec.b.x",
    "let rec$0 = ({a: 1, b: ({x: 5})});\nrec$0.b.x",
    5,
  )
  test_compilation(
    "{a: 1, b: let x = 2 x}.b",
    "let x$9 = 2;\n({a: 1, b: x$9}).b",
    2,
  )
  test_compilation(
    "{a: 1, b: (x) -> { x }(3)}.b",
    "({a: 1, b: ((x$10) => {\n  return x$10;\n})(3)}).b",
    3,
  )
  test_compilation(
    "{a: 1, b: (x) -> { x }}.b(3)",
    "({a: 1, b: ((x$10) => {\n  return x$10;\n})}).b(3)",
    3,
  )
}

pub fn overwrite_test() {
  test_compilation(
    "let x = {a: 7, b: 8}
    {b: 3, ..x}",
    "let x$0 = ({a: 7, b: 8});\n({...x$0, b: 3})",
    json.object([#("a", json.int(7)), #("b", json.int(3))]),
  )
  test_compilation(
    "let x = {a: 7, b: 8}
    {b: 3, a: 1, ..x}",
    "let x$0 = ({a: 7, b: 8});\n({...x$0, b: 3, a: 1})",
    json.object([#("a", json.int(1)), #("b", json.int(3))]),
  )
  test_compilation(
    "let x = {a: 7, b: 8}
    {a: let z = 3 z, ..x}",
    "let x$0 = ({a: 7, b: 8});\nlet z$13 = 3;\n({...x$0, a: z$13})",
    json.object([#("a", json.int(3)), #("b", json.int(8))]),
  )
  test_compilation(
    "{a: 5, ..{a: 7}}",
    "({...({a: 7}), a: 5})",
    json.object([#("a", json.int(5))]),
  )
  test_compilation(
    "{a: 5, ..let z = {a: 2} z}",
    "let z$4 = ({a: 2});\n({...z$4, a: 5})",
    json.object([#("a", json.int(5))]),
  )

  test_compilation(
    "{a: 1, ..(x) -> { {a: x} }(6)}",
    "({...((x$5) => {\n  return ({a: x$5});\n})(6), a: 1})",
    json.object([#("a", json.int(1))]),
  )
}

// Don't need many of these because we have tests for let and select
pub fn destructuring_test() {
  test_compilation(
    "({a}) -> { a }({a: 7})",
    "(($$1) => {\n  let a$2 = $$1.a;\n  return a$2;\n})(({a: 7}))",
    7,
  )
}

pub fn case_test() {
  // first branch
  test_compilation(
    "match Ok(2) {
      Ok(a) -> { a }
      Error(_) -> { 3 }
    }",
    "(function($) { switch ($.$T) {\ncase 'Ok':   return ((a$4) => {\n  return a$4;\n})($.$V)\ncase 'Error':   return ((_$9) => {\n  return 3;\n})($.$V)\n}})({$T: \"Ok\", $V: 2})",
    2,
  )
  // second branch
  test_compilation(
    "match Error(2) {
      Ok(a) -> { a }
      Error(_) -> { 3 }
    }",
    "(function($) { switch ($.$T) {\ncase 'Ok':   return ((a$4) => {\n  return a$4;\n})($.$V)\ncase 'Error':   return ((_$9) => {\n  return 3;\n})($.$V)\n}})({$T: \"Error\", $V: 2})",
    3,
  )
}

pub fn case_other_branch_test() {
  test_compilation(
    "match Foo(2) {
      Ok(a) -> { a }
      | (x) -> { x }
    }",
    "(function($) { switch ($.$T) {\ncase 'Ok':   return ((a$4) => {\n  return a$4;\n})($.$V)\ndefault:   return ((x$6) => {\n  return x$6;\n})($)}})({$T: \"Foo\", $V: 2})",
    json.object([#("$T", json.string("Foo")), #("$V", json.int(2))]),
  )
}

pub fn first_class_case_test() {
  // first branch
  test_compilation(
    "let m = match {
      Ok(a) -> { a }
      Error(_) -> { 3 }
    }
    m(Ok(2))",
    "let m$0 = (function($) { switch ($.$T) {\ncase 'Ok':   return ((a$4) => {\n  return a$4;\n})($.$V)\ncase 'Error':   return ((_$9) => {\n  return 3;\n})($.$V)\n}});\nm$0({$T: \"Ok\", $V: 2})",
    2,
  )
}

pub fn effect_test() {
  test_eval(
    "let x = perform Ask({})
    let y = perform Ask({})
    !int_add(x, y)",
    20,
  )
}

fn tagged(label, value) {
  json.object([#("$T", json.string(label)), #("$V", value)])
}

fn unit() {
  json.object([])
}

pub fn compile_builtin_test() {
  // test_eval("!fix((f, ) -> {})", tagged("Lt", unit()))

  test_eval("!int_compare(1, 2)", tagged("Lt", unit()))
  test_compilation(
    "!int_add(1, 2)",
    "let int_add = (x) => (y) => x + y;
int_add(1)(2)",
    3,
  )
  test_eval("!int_subtract(3, 2)", 1)
  test_eval("!int_multiply(3, 2)", 6)
  test_eval("!int_divide(7, 2)", 3)
  test_eval("!int_parse(\"0\")", tagged("Ok", json.int(0)))
  test_eval("!int_to_string(100)", "100")
  test_eval("!string_append(\"ab\")(\"cd\")", "abcd")
  // test_eval("!string_split", 1)
  // test_eval("!string_split_once", 1)
  // test_eval("!string_replace", 1)
  test_eval("!string_uppercase(\"aBc\")", "ABC")
  test_eval("!string_lowercase(\"XyZ\")", "xyz")
  test_eval(
    "!string_starts_with(\"Hello\")(\"H\")",
    tagged("Ok", json.string("ello")),
  )
  test_eval("!string_ends_with(\"Hello\")(\"H\")", tagged("Error", unit()))
  test_eval("!string_length(\"Yo\")", 2)
  // test_eval("!pop_grapheme", 1)
  // test_eval("!string_to_binary", 1)

  test_eval(
    "!list_pop([1, 2, 3])",
    tagged(
      "Ok",
      json.object([
        #("head", json.int(1)),
        #("tail", dynamicx.unsafe_coerce(dynamic.from(#(2, #(3, #()))))),
      ]),
    ),
  )
  test_compilation(
    "!list_fold([1, 2, 3], 0, !int_add)",
    "let list_fold = (items) => (acc) => (f) => {\n  let item;\n  while (items.length != 0) {\n    item = items[0];\n    items = items[1];\n    acc = f(acc)(item);\n  }\n  return acc\n};\nlet int_add = (x) => (y) => x + y;\nlist_fold([1, [2, [3, []]]])(0)(int_add)",
    6,
  )
}
