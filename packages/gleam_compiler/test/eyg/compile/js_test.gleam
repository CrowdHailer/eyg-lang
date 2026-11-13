import eyg/compiler
import eyg/compiler/js
import eyg/parser
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/javascript/array.{type Array}
import gleam/json
import gleam/list
import gleam/pair
import gleeunit/should
import plinth/browser/window.{eval}

@external(javascript, "./js_ffi.mjs", "list")
fn do_list(items: Array(Dynamic)) -> Dynamic

/// This is needed because dynamic.list creates nested head/tail tuples
fn list(items, encode) {
  items
  |> list.map(encode)
  |> array.from_list()
  |> do_list
}

@external(javascript, "./js_ffi.mjs", "object")
fn do_object(items: Array(#(String, Dynamic))) -> Dynamic

/// This is needed because dynamic.properties creates a dictionary
fn object(items) {
  items
  |> array.from_list
  |> do_object
}

fn tagged(label, value) -> Dynamic {
  object([#("$T", dynamic.string(label)), #("$V", value)])
}

fn unit() -> Dynamic {
  object([])
}

fn test_compilation(source, js, evaled) {
  let generated =
    source
    |> parser.from_string()
    |> should.be_ok()
    |> pair.first()
    |> compiler.to_js(dict.new(), js.basic)
  generated
  |> should.equal(js)
  generated
  |> eval()
  |> should.be_ok()
  |> should.equal(evaled)
}

fn test_eval(source, evaled) {
  let generated =
    source
    |> parser.from_string()
    |> should.be_ok()
    |> pair.first()
    |> compiler.to_js(dict.new(), js.basic)
  generated
  |> eval()
  |> should.be_ok()
  |> should.equal(evaled)
}

pub fn query_fact_set_test() {
  test_eval(
    "resolve Number @{ fact Number(1), fact Number(1), fact Number(2) }",
    list([1, 2], dynamic.int),
  )
}

pub fn query_recursive_join_test() {
  test_eval(
    "let view = @{
    rule Reach({from, to}) { var from var to Edge({from, to}) }
    rule Reach({from, to}) {
      var from var to var middle
      Edge({from, to: middle}), Reach({from: middle, to})
    }
  }
  resolve Out @{
    view, fact Edge({from: 1, to: 2}), fact Edge({from: 2, to: 3}),
    rule Out(to) { var to Reach({from: 1, to}) }
  }",
    list([2, 3], dynamic.int),
  )
}

pub fn query_pure_head_and_boolean_predicates_test() {
  test_eval(
    "resolve Out @{
    fact Number(2),
    rule Out(!int_add(n, 1)) { var n Number(n), True({}) },
    rule Out(100) { False({}) }
  }",
    list([3], dynamic.int),
  )
}

pub fn unchecked_query_effects_cannot_reach_the_host_or_outer_handler_test() {
  list.each(
    [
      "resolve Out @{ rule Out(perform Nope({})) {} }",
      "handle Nope((_, resume) -> { resume(1) }, (_) -> {
      resolve Out @{ rule Out(perform Nope({})) {} }
    })",
    ],
    fn(source) {
      let program = source |> parser.all_from_string |> should.be_ok
      let code =
        compiler.to_js(program, dict.new(), "() => { calls++; return 1; }")
      let script =
        "(() => { let calls = 0; try { eval("
        <> json.to_string(json.string(code))
        <> "); return 'unexpected success'; } catch (e) { return calls + ':' + e.eygBreak?.ImpureQuery; } })()"
      script |> eval |> should.be_ok |> should.equal(dynamic.string("0:Nope"))
    },
  )
}

pub fn several_let_bindings_in_an_argument_test() {
  test_eval("!int_add(1, let a = 2 let b = 3 !int_add(a, b))", dynamic.int(6))
}

pub fn literal_test() {
  test_compilation(
    "let num = 5
    num",
    "let num$0 = 5;
num$0",
    dynamic.int(5),
  )

  test_compilation(
    "let str = \"hello\"
    str",
    "let str$0 = \"hello\";
str$0",
    dynamic.string("hello"),
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
    dynamic.int(2),
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
    dynamic.int(80),
  )
  // shadowing
  test_compilation(
    "let x = 1
    let x = 2
    x",
    "let x$0 = 1;
let x$2 = 2;
x$2",
    dynamic.int(2),
  )
}

pub fn iife_test() {
  test_compilation(
    "(x) -> { x }(2)",
    "((x$1) => {\n  return x$1;\n})(2)",
    dynamic.int(2),
  )
  test_compilation(
    "(x, y) -> { y }(2, 7)",
    // literals dont need curl and return for body useful for multiarity fns
    "((x$2) => {\n  return ((y$3) => {\n  return y$3;\n});\n})(2)(7)",
    dynamic.int(7),
  )
}

pub fn list_test() {
  test_compilation("[1, 2]", "[1, [2, []]]", list([1, 2], dynamic.int))
  test_compilation(
    "let x = [3, 2]
      x",
    "let x$0 = [3, [2, []]];
x$0",
    list([3, 2], dynamic.int),
  )
  test_compilation(
    "[(x) -> { x }(1), 2]",
    "[((x$4) => {\n  return x$4;\n})(1), [2, []]]",
    list([1, 2], dynamic.int),
  )
  test_compilation(
    "[let y = 5 y]",
    "let y$3 = 5;
[y$3, []]",
    list([5], dynamic.int),
  )
}

pub fn record_test() {
  test_compilation("{}", "({})", unit())
  test_compilation("{a: 4}.a", "({a: 4}).a", dynamic.int(4))
  test_compilation(
    "let rec = {a: 1, b: 7}
    rec.a",
    "let rec$0 = ({a: 1, b: 7});\nrec$0.a",
    dynamic.int(1),
  )
  test_compilation(
    "let rec = {a: 1, b: 7}
    rec.b",
    "let rec$0 = ({a: 1, b: 7});\nrec$0.b",
    dynamic.int(7),
  )
  test_compilation(
    "let rec = {a: 1, b: {x: 5}}
    rec.b.x",
    "let rec$0 = ({a: 1, b: ({x: 5})});\nrec$0.b.x",
    dynamic.int(5),
  )
  test_compilation(
    "{a: 1, b: let x = 2 x}.b",
    "let x$9 = 2;\n({a: 1, b: x$9}).b",
    dynamic.int(2),
  )
  test_compilation(
    "{a: 1, b: (x) -> { x }(3)}.b",
    "({a: 1, b: ((x$10) => {\n  return x$10;\n})(3)}).b",
    dynamic.int(3),
  )
  test_compilation(
    "{a: 1, b: (x) -> { x }}.b(3)",
    "({a: 1, b: ((x$10) => {\n  return x$10;\n})}).b(3)",
    dynamic.int(3),
  )
}

pub fn overwrite_test() {
  test_compilation(
    "let x = {a: 7, b: 8}
    {b: 3, ..x}",
    "let x$0 = ({a: 7, b: 8});\n({...x$0, b: 3})",
    object([#("a", dynamic.int(7)), #("b", dynamic.int(3))]),
  )
  test_compilation(
    "let x = {a: 7, b: 8}
    {b: 3, a: 1, ..x}",
    "let x$0 = ({a: 7, b: 8});\n({...x$0, b: 3, a: 1})",
    object([#("a", dynamic.int(1)), #("b", dynamic.int(3))]),
  )
  test_compilation(
    "let x = {a: 7, b: 8}
    {a: let z = 3 z, ..x}",
    "let x$0 = ({a: 7, b: 8});\nlet z$13 = 3;\n({...x$0, a: z$13})",
    object([#("a", dynamic.int(3)), #("b", dynamic.int(8))]),
  )
  test_compilation(
    "{a: 5, ..{a: 7}}",
    "({...({a: 7}), a: 5})",
    object([#("a", dynamic.int(5))]),
  )
  test_compilation(
    "{a: 5, ..let z = {a: 2} z}",
    "let z$4 = ({a: 2});\n({...z$4, a: 5})",
    object([#("a", dynamic.int(5))]),
  )

  test_compilation(
    "{a: 1, ..(x) -> { {a: x} }(6)}",
    "({...((x$5) => {\n  return ({a: x$5});\n})(6), a: 1})",
    object([#("a", dynamic.int(1))]),
  )
}

// Don't need many of these because we have tests for let and select
pub fn destructuring_test() {
  test_compilation(
    "({a}) -> { a }({a: 7})",
    "(($$1) => {\n  let a$2 = $$1.a;\n  return a$2;\n})(({a: 7}))",
    dynamic.int(7),
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
    dynamic.int(2),
  )
  // second branch
  test_compilation(
    "match Error(2) {
      Ok(a) -> { a }
      Error(_) -> { 3 }
    }",
    "(function($) { switch ($.$T) {\ncase 'Ok':   return ((a$4) => {\n  return a$4;\n})($.$V)\ncase 'Error':   return ((_$9) => {\n  return 3;\n})($.$V)\n}})({$T: \"Error\", $V: 2})",
    dynamic.int(3),
  )
}

pub fn case_other_branch_test() {
  test_compilation(
    "match Foo(2) {
      Ok(a) -> { a }
      | (x) -> { x }
    }",
    "(function($) { switch ($.$T) {\ncase 'Ok':   return ((a$4) => {\n  return a$4;\n})($.$V)\ndefault:   return ((x$6) => {\n  return x$6;\n})($)}})({$T: \"Foo\", $V: 2})",
    tagged("Foo", dynamic.int(2)),
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
    dynamic.int(2),
  )
}

pub fn effect_test() {
  test_eval(
    "let x = perform Ask({})
    let y = perform Ask({})
    !int_add(x, y)",
    dynamic.int(20),
  )
}

pub fn compile_builtin_test() {
  test_eval("!int_compare(1, 2)", tagged("Lt", unit()))
  test_compilation(
    "!int_add(1, 2)",
    "let int_add = (x) => (y) => x + y;
int_add(1)(2)",
    dynamic.int(3),
  )
  test_eval("!int_subtract(3, 2)", dynamic.int(1))
  test_eval("!int_multiply(3, 2)", dynamic.int(6))
  test_eval("!int_divide(7, 2)", tagged("Ok", dynamic.int(3)))
  test_eval("!int_parse(\"0\")", tagged("Ok", dynamic.int(0)))
  test_eval("!int_to_string(100)", dynamic.string("100"))
  test_eval("!string_append(\"ab\")(\"cd\")", dynamic.string("abcd"))
  test_eval("!string_uppercase(\"aBc\")", dynamic.string("ABC"))
  test_eval("!string_lowercase(\"XyZ\")", dynamic.string("xyz"))
  test_eval("!string_starts_with(\"Hello\")(\"H\")", tagged("True", unit()))
  test_eval("!string_ends_with(\"Hello\")(\"H\")", tagged("False", unit()))
  test_eval("!string_length(\"Yo\")", dynamic.int(2))
  test_eval(
    "!list_pop([1, 2, 3])",
    tagged(
      "Ok",
      object([
        #("head", dynamic.int(1)),
        #("tail", list([2, 3], dynamic.int)),
      ]),
    ),
  )
  test_eval("!list_fold([1, 2, 3], 0, !int_add)", dynamic.int(6))
}

// Regressions from the compiler investigation, before replacing the backend.
pub fn builtin_semantics_regressions_test() {
  test_eval("!int_compare(2, 1)", tagged("Gt", unit()))
  test_eval("!int_compare(2, 2)", tagged("Eq", unit()))
  test_eval("!int_divide(7, 0)", tagged("Error", unit()))
  test_eval("!int_parse(\"12junk\")", tagged("Error", unit()))
  test_eval("!int_parse(\" 12\")", tagged("Error", unit()))
  test_eval("!list_fold([1, 2, 3], 0, !int_subtract)", dynamic.int(2))
}
