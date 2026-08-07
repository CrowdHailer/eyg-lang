import eyg/cli/internal/config
import eyg/cli/internal/source
import eyg/ir/dag_json
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/json

pub fn execute(
  input: source.Input,
  _config: config.Config,
) -> promise.Promise(Result(Int, String)) {
  use code <- promisex.try_sync(source.read_input(input))
  use source <- promisex.try_sync(source.parse_input(code, input))
  io.println(json.to_string(dag_json.to_data_model(source)))
  promise.resolve(Ok(0))
}
