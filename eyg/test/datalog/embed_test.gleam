import gleam/dict
import gleam/io
import eygir/annotated as e
import eyg/parse/lexer
import eyg/parse/parser
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import gleeunit/should

pub fn next_test() {
  "solve T(query {
        T(x: 3, y: 2).
        T(x: 2, y: 1).
    })"
  |> lexer.lex()
  |> parser.parse()
  // |> io.debug
  |> should.be_ok
  |> e.drop_annotation()
  |> io.debug
  |> r.execute(state.Env(scope: [], builtins: dict.new()), dict.new())
  |> should.be_ok
  |> v.debug
  |> io.debug
  //   todo
}
// TODO CEK
// TODO infer
