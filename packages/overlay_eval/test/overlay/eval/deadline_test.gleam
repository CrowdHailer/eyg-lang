import gleam/javascript/promise
import gleeunit/should
import overlay/eval/deadline
import plinthx/node/timers

pub fn stalled_work_fails_test() {
  let stalled = promise.new(fn(_) { Nil })
  use result <- promise.map(deadline.within(stalled, 5, "timed out"))
  result |> should.equal(Error("timed out"))
}

pub fn completed_work_clears_its_timer_test() {
  use result <- promise.map(deadline.within(
    promise.resolve(Ok(42)),
    1000,
    "timed out",
  ))
  result |> should.equal(Ok(42))
}

pub fn a_disabled_deadline_waits_for_work_test() {
  let work = timers.sleep(10) |> promise.map(fn(_) { Ok(42) })
  use result <- promise.map(deadline.within(work, 0, "timed out"))
  result |> should.equal(Ok(42))
}
