import etui/app
import etui/backend
import etui/backend/default
import eyg/cli/internal/config
import eyg/cli/shell
import eyg/cli/tui/state
import eyg/cli/tui/view
import eyg/hub/cache
import gleam/javascript/promise
import gleam/option.{type Option}
import loam/execute
import loam/source
import loam/system

pub fn execute(
  input: Option(source.Input),
  config: config.Config,
) -> promise.Promise(Result(Int, String)) {
  let state = execute.State(config.client.origin, cache.empty())
  use #(scope, state) <- promise.try_await(
    system.run(shell.read_input(input, state)),
  )

  use _ <- promise.map(
    app.run_buffered(
      default.new_with_options(backend.Options(mouse: True, paste: True)),
      state.init(scope, state),
      view.render,
      state.update,
      fn(m) { m.quit },
      fn(_) { 16 },
    ),
  )
  Ok(0)
}
