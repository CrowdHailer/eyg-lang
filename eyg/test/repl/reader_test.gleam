import glance
import repl/reader
import gleeunit/should

pub fn attribute_test() {
  "@external(javascript)"
  |> reader.parse()
  |> should.equal(Error(reader.Unsupported("attributes")))
}

pub fn simple_import_test() {
  "import lib/foo"
  |> reader.parse()
  |> should.equal(Ok(#(reader.Import("lib/foo", "foo", []), [])))
}

pub fn aliased_import_test() {
  "import lib/foo as bar"
  |> reader.parse()
  |> should.equal(Ok(#(reader.Import("lib/foo", "bar", []), [])))
}

pub fn import_fields_test() {
  "import lib/foo.{a, b}"
  |> reader.parse()
  |> should.equal(
    Ok(#(reader.Import("lib/foo", "foo", [#("a", "a"), #("b", "b")]), [])),
  )
}

pub fn import_aliased_fields_test() {
  "import lib/foo.{a as x, b as y}"
  |> reader.parse()
  |> should.equal(
    Ok(#(reader.Import("lib/foo", "foo", [#("a", "x"), #("b", "y")]), [])),
  )
}

pub fn public_constant_test() {
  "pub const x = 5"
  |> reader.parse()
  |> should.equal(Ok(#(reader.Constant("x", glance.Int("5")), [])))
}

pub fn private_constant_test() {
  "const x = 5"
  |> reader.parse()
  |> should.equal(Ok(#(reader.Constant("x", glance.Int("5")), [])))
}

pub fn public_function_test() {
  "pub fn foo() { 5 }"
  |> reader.parse()
  |> should.equal(
    Ok(#(reader.Function("foo", [], [glance.Expression(glance.Int("5"))]), [])),
  )
}

pub fn private_function_test() {
  "fn foo() { 5 }"
  |> reader.parse()
  |> should.equal(
    Ok(#(reader.Function("foo", [], [glance.Expression(glance.Int("5"))]), [])),
  )
}
// things that are not supported
