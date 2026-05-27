import eyg/cli/internal/config
import eyg/cli/internal/execute
import eyg/cli/internal/source
import eyg/hub/cache
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/option.{None, Some}
import gleam/result
import simplifile

pub fn execute(
  input: source.Input,
  config: config.Config,
) -> promise.Promise(Result(Int, String)) {
  use cwd <- promisex.try_sync(
    simplifile.current_directory()
    |> result.map_error(simplifile.describe_error),
  )
  use input <- promisex.try_sync(execute.normalize_input(cwd, input))
  use code <- promisex.try_sync(source.read_input(input))
  use source <- promisex.try_sync(source.parse_input(code, input))

  let state = execute.State(config, cache.empty())
  use result <- promise.map(execute.block(source, [], state))
  case result {
    Ok(#(Some(_value), _)) -> Ok(0)
    Ok(#(None, _)) -> Ok(0)
    Error(#(reason, location, _, k)) -> {
      Error(execute.render_error(reason, location, k, cwd))
    }
  }
}
