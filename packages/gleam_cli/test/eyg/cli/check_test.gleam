import eyg/cli/check
import eyg/cli/helpers
import eyg/cli/internal/source
import gleam/string

pub fn check_simple_expression_test() {
  let input = source.Code("3")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(helpers.sandbox())
  assert Ok(0) == output
  assert ["Integer"] == sandbox.stdout
}

pub fn check_fails_test() {
  let input = source.Code("x")
  let #(output, sandbox) =
    check.execute(input, helpers.config)
    |> helpers.run(helpers.sandbox())
  let assert Error(message) = output
  let assert [] = sandbox.stdout
  assert string.contains(message, "missing variable")
}
