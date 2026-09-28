import eyg/cli/compile
import eyg/cli/helpers
import eyg/cli/internal/source
import loam/sandbox

pub fn compile_simple_expression_test() {
  let input = source.Code("3")
  let #(output, sandbox) =
    compile.execute(input, helpers.config)
    |> sandbox.run(sandbox.sandbox())
  assert Ok(0) == output
  assert ["3"] == sandbox.stdout
}

pub fn compile_stdin_test() {
  let sandbox = sandbox.sandbox() |> sandbox.with_stdin("45")
  let input = source.Stdin
  let #(output, sandbox) =
    compile.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  assert Ok(0) == output
  assert ["45"] == sandbox.stdout
}

pub fn compile_file_test() {
  let sandbox = sandbox.sandbox() |> sandbox.with_file("/main.eyg", "145")
  let input = source.File("/main.eyg")
  let #(output, sandbox) =
    compile.execute(input, helpers.config)
    |> sandbox.run(sandbox)
  assert Ok(0) == output
  assert ["145"] == sandbox.stdout
}
