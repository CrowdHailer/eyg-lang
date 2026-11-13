import cloud/cron
import gleam/time/timestamp

// 2026-11-12 is a Thursday.
fn at(hours, minutes, seconds) {
  let midnight = 1_794_441_600
  timestamp.from_unix_seconds(midnight + hours * 3600 + minutes * 60 + seconds)
}

pub fn every_minute_test() {
  let assert Ok(schedule) = cron.parse("* * * * *")
  assert cron.matches(schedule, at(9, 30, 0))
  assert !cron.matches(schedule, at(9, 30, 1))
}

pub fn seconds_field_test() {
  let assert Ok(schedule) = cron.parse("*/20 * * * * *")
  assert cron.matches(schedule, at(9, 30, 40))
  assert !cron.matches(schedule, at(9, 30, 41))
}

pub fn weekdays_at_nine_test() {
  let assert Ok(schedule) = cron.parse("0 9 * * 1-5")
  assert cron.matches(schedule, at(9, 0, 0))
  assert !cron.matches(schedule, at(10, 0, 0))
  let assert Ok(weekend) = cron.parse("0 9 * * 0,6")
  assert !cron.matches(weekend, at(9, 0, 0))
  let assert Ok(thursday) = cron.parse("0 9 12 11 4")
  assert cron.matches(thursday, at(9, 0, 0))
}

pub fn ranges_with_steps_test() {
  let assert Ok(schedule) = cron.parse("10-30/10 * * * *")
  assert cron.matches(schedule, at(1, 20, 0))
  assert !cron.matches(schedule, at(1, 25, 0))
  assert !cron.matches(schedule, at(1, 40, 0))
}

pub fn invalid_schedules_test() {
  let assert Error(_) = cron.parse("* * *")
  let assert Error(_) = cron.parse("61 * * * *")
  let assert Error(_) = cron.parse("*/0 * * * *")
  let assert Error(_) = cron.parse("a * * * *")
}
