import eyg/cli/internal/config
import eyg/cli/internal/execute
import eyg/cli/internal/source
import eyg/hub/cache
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import filepath
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/result
import simplifile

pub fn execute(
  file: String,
  config: config.Config,
) -> promise.Promise(Result(Nil, String)) {
  use source <- promisex.try_sync(source.read(file))

  use cwd <- promisex.try_sync(
    simplifile.current_directory()
    |> result.map_error(simplifile.describe_error),
  )
  use path <- promisex.try_sync(execute.resolve_relative(cwd, file))
  let dir = filepath.directory_name(path)
  let state = execute.State(dir, config, cache.empty(), fn(_: Nil) { Nil })
  use result <- promise.map(execute.pure_loop(
    expression.execute(source, []),
    state,
  ))
  case result {
    Ok(value) -> {
      io.println(simple_debug.inspect(value))
      Ok(Nil)
    }
    Error(reason) -> Error(simple_debug.describe(reason))
  }
}
