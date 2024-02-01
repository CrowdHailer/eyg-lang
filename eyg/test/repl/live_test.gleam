import gleam/dict
import gleam/list
import glexer
import glance
import scintilla/value as v
import repl/runner as r_runner
import gleeunit/should

fn exec(src, env) {
  src
  |> glance.statements()
  |> should.be_ok()
  |> r_runner.live_exec(env)
}

// needs to be list to be constant
// const env = dict.new()

pub fn function_bind_test() {
  "fn(a, b){ 0 }(1, #())"
  |> exec(dict.new())
  |> should.equal(#(Ok(v.I(0)), [[#("a", v.I(1)), #("b", v.T([]))]]))
}

pub fn case_bind_test() {
  "case 7, 8 {
    c, d -> 0
  }"
  |> exec(dict.new())
  |> should.equal(#(Ok(v.I(0)), [[#("c", v.I(7)), #("d", v.I(8))]]))
}
