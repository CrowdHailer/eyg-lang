import eyg/ir/tree as ir
import loam/sandbox
import loam/source
import loam/system

pub fn read_code_test() {
  let assert system.Done(Ok(code)) =
    source.Code("!int_add(1, 1)")
    |> source.read_input()

  let assert Ok(source) = source.parse_input(code, source.Stdin)
  assert ir.apply(ir.apply(ir.builtin("int_add"), ir.integer(1)), ir.integer(1))
    == ir.clear_annotation(source)
}

pub fn file_loading_strips_shebangs_test() {
  let sandbox =
    sandbox.sandbox() |> sandbox.with_file("/entry", "#!/usr/bin/env eyg\n11")
  let #(read, _) =
    source.read_input(source.File("/entry")) |> sandbox.run(sandbox)
  assert read == Ok("11")
}
