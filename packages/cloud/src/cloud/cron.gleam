//// Cron schedules, evaluated in UTC.
////
//// A schedule has five fields, `minute hour day-of-month month day-of-week`,
//// or six with a leading `second` field. Each field is `*`, a number, a range `1-5`,
//// a step `*/15` or `1-30/5`, or a comma separated list of those.
//// Day of week is 0 to 6 starting on Sunday, 7 is also Sunday.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp.{type Timestamp}

pub opaque type Schedule {
  Schedule(
    seconds: List(Int),
    minutes: List(Int),
    hours: List(Int),
    days: List(Int),
    months: List(Int),
    weekdays: List(Int),
  )
}

pub fn parse(text: String) -> Result(Schedule, String) {
  let fields =
    string.split(string.trim(text), " ") |> list.filter(fn(f) { f != "" })
  let fields = case fields {
    [_, _, _, _, _] -> Ok(["0", ..fields])
    [_, _, _, _, _, _] -> Ok(fields)
    _ -> Error("a cron schedule has 5 or 6 fields: " <> text)
  }
  use fields <- result.try(fields)
  let assert [second, minute, hour, day, month, weekday] = fields
  use seconds <- result.try(field(second, 0, 59))
  use minutes <- result.try(field(minute, 0, 59))
  use hours <- result.try(field(hour, 0, 23))
  use days <- result.try(field(day, 1, 31))
  use months <- result.try(field(month, 1, 12))
  use weekdays <- result.try(field(weekday, 0, 7))
  let weekdays =
    list.map(weekdays, fn(d) {
      case d {
        7 -> 0
        d -> d
      }
    })
  Ok(Schedule(seconds:, minutes:, hours:, days:, months:, weekdays:))
}

fn field(text: String, low: Int, high: Int) -> Result(List(Int), String) {
  string.split(text, ",")
  |> list.try_map(fn(part) {
    let #(range, step) = case string.split_once(part, "/") {
      Ok(#(range, step)) -> #(range, int.parse(step))
      Error(Nil) -> #(part, Ok(1))
    }
    use step <- result.try(case step {
      Ok(step) if step > 0 -> Ok(step)
      _ -> Error("invalid step in " <> part)
    })
    use #(from, to) <- result.try(case range {
      "*" -> Ok(#(low, high))
      _ ->
        case string.split_once(range, "-") {
          Ok(#(from, to)) ->
            case int.parse(from), int.parse(to) {
              Ok(from), Ok(to) -> Ok(#(from, to))
              _, _ -> Error("invalid range " <> range)
            }
          Error(Nil) ->
            case int.parse(range) {
              Ok(value) -> Ok(#(value, value))
              Error(Nil) -> Error("invalid value " <> range)
            }
        }
    })
    case from < low || to > high || from > to {
      True ->
        Error(
          part
          <> " is outside "
          <> int.to_string(low)
          <> "-"
          <> int.to_string(high),
        )
      False ->
        Ok(
          int.range(from, to + 1, [], fn(acc, i) { [i, ..acc] })
          |> list.reverse
          |> list.filter(fn(value) { { value - from } % step == 0 }),
        )
    }
  })
  |> result.map(list.flatten)
}

/// Does the schedule run in the second of `time`.
pub fn matches(schedule: Schedule, time: Timestamp) -> Bool {
  let #(date, clock) = timestamp.to_calendar(time, calendar.utc_offset)
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(time)
  // 1970-01-01 was a Thursday, day 4 counting from Sunday.
  let weekday = { { seconds / 86_400 } + 4 } % 7
  list.contains(schedule.seconds, clock.seconds)
  && list.contains(schedule.minutes, clock.minutes)
  && list.contains(schedule.hours, clock.hours)
  && list.contains(schedule.days, date.day)
  && list.contains(schedule.months, calendar.month_to_int(date.month))
  && list.contains(schedule.weekdays, weekday)
}
