import eyg/cli/internal/config
import eyg/hub/cache
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
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
  use #(result, _) <- system.then(execute.pure_loop(
    expression.execute(source, []),
    state,
  ))
  case result {
    Ok(value) -> {
      use Nil <- system.map(system.stdout(simple_debug.inspect(value)))
      Ok(0)
    }
    Error(#(reason, location, _env, k)) ->
      system.Done(Error(execute.render_error(reason, location, k, cwd)))
  }
}
