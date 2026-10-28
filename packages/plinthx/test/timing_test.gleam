import plinthx/browser/abort_signal
import plinthx/browser/performance

pub fn high_resolution_clock_is_monotonic_test() {
  let assert Ok(clock) = performance.get()
  let before = performance.now(clock)
  assert performance.now(clock) >=. before
  assert performance.time_origin(clock) >. 0.0
}

pub fn invalid_timeouts_return_errors_test() {
  let assert Ok(signal) = abort_signal.get()
  let assert Error(_) = abort_signal.timeout(signal, -1)
}
