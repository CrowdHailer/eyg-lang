import eyg/cli/internal/config
import eyg/cli/shell
import eyg/cli/tui/state
import eyg/cli/tui/terminal
import eyg/cli/tui/view
import gleam/javascript/promise
import gleam/option.{type Option}
import loam/source
import loam/system

pub fn execute(
  input: Option(source.Input),
  config: config.Config,
) -> promise.Promise(Result(Int, String)) {
  use #(scope, execution) <- promise.try_await(
    system.run(shell.read_input(input, config.state(config))),
  )
  terminal.run(
    state.init(scope, execution),
    fn(state, event) {
      state.update(state, case event {
        terminal.Input(event) -> state.Input(event)
        terminal.Task(message) -> state.Task(message)
      })
    },
    view.render,
    fn(state) { state.quit },
  )
}

pub type ContinueOrStop(state, return) {
  Continue(state)
  Stop(return)
}

pub fn apply_until(
  over list: List(a),
  from initial: acc,
  with fun: fn(acc, a) -> ContinueOrStop(acc, return),
) -> ContinueOrStop(acc, return) {
  case list {
    [] -> Continue(initial)
    [first, ..rest] ->
      case fun(initial, first) {
        Continue(next_accumulator) -> apply_until(rest, next_accumulator, fun)
        Stop(b) -> Stop(b)
      }
  }
}
