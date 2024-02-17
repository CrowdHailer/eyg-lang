import glexer
import glexer/token
import gleeunit/should

pub fn demo_test() {
  glexer.new("\"abc")
  |> glexer.lex()
  |> should.equal([#(token.String(""), glexer.Position(1))])
  todo
}
