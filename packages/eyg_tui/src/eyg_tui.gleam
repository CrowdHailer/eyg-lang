//// Run main's structural editor and history on the BEAM.

import argv
import etui/app
import etui/backend/default
import eyg/cli/args
import eyg/cli/shell
import eyg/cli/tui/state
import eyg/cli/tui/view
import eyg/hub/cache
import eyg_tui/host
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import loam/execute
import ogre/origin

pub fn main() {
  case args.parse(["tui", ..argv.load().arguments]) {
    args.Tui(input) -> {
      let initial = execute.State(origin.https("eyg.run"), cache.ready(), None)
      case host.run(shell.read_input(input, initial)) |> result.flatten {
        Error(reason) -> io.println_error(reason)
        Ok(#(scope, execution)) -> {
          let result =
            app.run_buffered(
              default.new(),
              state.init(scope, execution),
              view.render,
              fn(event, current) {
                let #(next, effects) = state.update(current, state.Input(event))
                drain(next, effects)
              },
              fn(current) { current.quit },
              fn(_) { 16 },
            )
          case result {
            app.Success(_) -> Nil
            app.Error(reason) -> io.println_error(reason)
          }
        }
      }
    }
    _ -> io.println_error("usage: gleam run [<file>]; Overlay needs JavaScript")
  }
}

fn drain(current: state.State, effects) {
  list.fold(effects, current, fn(current, effect) {
    case host.run(effect) {
      Error(reason) ->
        state.State(..current, message: Some(reason), mode: state.Navigating)
      Ok(message) -> {
        let #(next, effects) = state.update(current, state.Task(message))
        drain(next, effects)
      }
    }
  })
}
