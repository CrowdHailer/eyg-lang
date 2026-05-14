import eyg/cli/internal/source
import eyg/ir/tree as ir
import gleeunit/should

pub fn read_code_test() {
  source.Code("!int_add(1, 1)")
  |> source.read_input()
  |> should.be_ok()
  |> should.equal(ir.apply(
    ir.apply(ir.builtin("int_add"), ir.integer(1)),
    ir.integer(1),
  ))
}

pub fn read_code_error_test() {
  source.Code("let x =")
  |> source.read_input()
  |> should.be_error()
}
