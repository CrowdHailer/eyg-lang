import eyg/cli/internal/source
import eyg/ir/tree as ir

pub fn read_code_test() {
  let assert Ok(code) =
    source.Code("!int_add(1, 1)")
    |> source.read_input()
  let assert Ok(source) = source.parse(code)
  assert ir.apply(ir.apply(ir.builtin("int_add"), ir.integer(1)), ir.integer(1))
    == ir.clear_annotation(source)
}
