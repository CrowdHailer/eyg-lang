import eyg/cli/internal/config
import loam/execute
import loam/profile
import loam/source
import loam/system

pub fn execute(input: source.Input, config: config.Config) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use input <- system.try(source.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use node <- system.try(source.parse_input(code, input))
  let runtime = config.state(config)
  use #(result, _) <- system.map(profile.block(node, [], runtime))
  case result {
    Ok(_) -> Ok(0)
    Error(#(reason, location, _, stack)) ->
      Error(execute.render_error(reason, location, stack, cwd))
  }
}
