import eyg/document/section.{Section}
import eyg/parse
import gleam/pair
import gleeunit/should
import gleeunit/shouldx
import morph/editable as e

fn ast(source) {
  source
  |> parse.from_string()
  |> should.be_ok()
  |> pair.first()
}

pub fn separate_on_comment_test() {
  let source =
    ast(
      "let _ = \"foo\"
    let x = 1
    let y = 2
    let _ = \"bar\"
    let _ = \"baz\"
    let z = 10
    todo
    ",
    )
  let #(s, _rest) = section.from_expression(source)
  let #(first, second) = shouldx.contain2(s)
  first
  |> should.equal(
    Section(["foo"], [
      #(e.Bind("x"), e.Integer(1)),
      #(e.Bind("y"), e.Integer(2)),
    ]),
  )
  second
  |> should.equal(Section(["bar", "baz"], [#(e.Bind("z"), e.Integer(10))]))
}
