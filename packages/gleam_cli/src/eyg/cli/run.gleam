import eyg/cli/internal/config
import eyg/hub/cache
import loam/execute
import loam/source
import loam/system

pub fn execute(
  input: source.Input,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use input <- system.try(source.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))

  let state = execute.State(config.client.origin, cache.empty())
  use result <- system.map(execute.block(source, [], state))
  case result {
    Ok(_) -> Ok(0)
    Error(#(reason, location, _, k)) -> {
      Error(execute.render_error(reason, location, k, cwd))
    }
  }
}
