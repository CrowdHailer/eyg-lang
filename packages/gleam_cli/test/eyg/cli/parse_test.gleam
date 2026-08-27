import eyg/cli/helpers
import eyg/cli/internal/source
import eyg/cli/parse
import gleam/string

pub fn parse_simple_expression_test() {
  let input = source.Code("3")
  let #(output, sandbox) =
    parse.execute(input, helpers.config)
    |> helpers.run(helpers.sandbox())
  assert Ok(0) == output
  assert ["{\"0\":\"i\",\"v\":3}"] == sandbox.stdout
}

pub fn parse_fails_test() {
  let input = source.Code(":")
  let #(output, sandbox) =
    parse.execute(input, helpers.config)
    |> helpers.run(helpers.sandbox())
  let assert Error(message) = output
  let assert [] = sandbox.stdout
  assert string.contains(message, "unexpected `:`")
}
