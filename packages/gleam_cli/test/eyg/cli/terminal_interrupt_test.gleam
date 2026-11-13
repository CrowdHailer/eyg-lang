import eyg/cli/internal/terminal
import gleam/javascript/promise
import plinthx/node/process
import plinthx/node/timers

pub fn real_signal_marks_only_the_active_turn_and_restart_resets_it_test() {
  let interrupt = terminal.interrupt()
  terminal.start_turn(interrupt)
  let assert Ok(host) = process.get()
  let assert Ok(_) = process.signal_self(host, "SIGINT")
  use _ <- promise.map(timers.sleep(20))
  assert terminal.interrupted(interrupt)
  terminal.end_turn(interrupt)
  terminal.start_turn(interrupt)
  assert !terminal.interrupted(interrupt)
  terminal.end_turn(interrupt)
}
