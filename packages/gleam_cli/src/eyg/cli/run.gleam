import eyg/cli/internal/config
import eyg/cli/internal/execute
import eyg/cli/internal/source
import eyg/hub/cache
import eyg/interpreter/simple_debug
import filepath
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/option.{None, Some}
import gleam/result
import simplifile

pub fn execute(
  input: source.Input,
  config: config.Config,
) -> promise.Promise(Result(Nil, String)) {
  use source <- promisex.try_sync(source.read_input(input))

  use cwd <- promisex.try_sync(
    simplifile.current_directory()
    |> result.map_error(simplifile.describe_error),
  )
  let dir = case input {
    source.File(path:) -> {
      use path <- result.try(execute.resolve_relative(cwd, path))
      Ok(filepath.directory_name(path))
    }
    source.Code(_) -> Ok(cwd)
  }
  use dir <- promisex.try_sync(dir)
  let state = execute.State(dir, config, cache.empty(), fn(_: Nil) { Nil })
  use result <- promise.map(execute.block(source, [], state))
  case result {
    Ok(#(Some(_value), _)) -> Ok(Nil)
    Ok(#(None, _)) -> Ok(Nil)
    Error(reason) -> Error(simple_debug.describe(reason))
  }
}
