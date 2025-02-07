import gleam/int
import gleam/string
import gleam/time/calendar.{Date}

pub fn date_to_string(date) {
  let Date(year, month, day) = date
  int.to_string(year)
  <> "-"
  <> string.pad_start(int.to_string(month_to_human_number(month)), 2, "0")
  <> "-"
  <> string.pad_start(int.to_string(day), 2, "0")
}

fn month_to_human_number(month) {
  case month {
    calendar.January -> 1
    calendar.February -> 2
    calendar.March -> 3
    calendar.April -> 4
    calendar.May -> 5
    calendar.June -> 6
    calendar.July -> 7
    calendar.August -> 8
    calendar.September -> 9
    calendar.October -> 10
    calendar.November -> 11
    calendar.December -> 12
  }
}
