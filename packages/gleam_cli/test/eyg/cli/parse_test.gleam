import eyg/cli/helpers
import eyg/cli/parse
import gleam/string
import loam/sandbox
import loam/source

pub fn parse_simple_expression_test() {
  let input = source.Code("3")
  let assert #(sandbox.Returned(output), sandbox) =
    parse.execute(input, helpers.config)
    |> sandbox.run(sandbox.sandbox())
  assert Ok(0) == output
  assert ["{\"0\":\"i\",\"v\":3}"] == sandbox.stdout
}

pub fn parse_fails_test() {
  let input = source.Code(":")
  let assert #(sandbox.Returned(output), sandbox) =
    parse.execute(input, helpers.config)
    |> sandbox.run(sandbox.sandbox())
  let assert Error(message) = output
  let assert [] = sandbox.stdout
  assert string.contains(message, "unexpected `:`")
}
