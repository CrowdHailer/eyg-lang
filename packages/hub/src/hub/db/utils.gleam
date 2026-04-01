import eyg/ir/dag_json
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/result
import gleam/time/calendar
import multiformats/cid/v1

pub type DateTime =
  #(calendar.Date, calendar.TimeOfDay)

pub fn datetime_decoder() {
  use date <- decode.field(0, {
    use year <- decode.field(0, decode.int)
    use month <- decode.field(1, {
      use month <- decode.then(decode.int)
      case calendar.month_from_int(month) {
        Ok(month) -> decode.success(month)
        Error(Nil) -> decode.failure(calendar.January, "Not a vald month")
      }
    })
    use day <- decode.field(2, decode.int)

    decode.success(calendar.Date(year:, month:, day:))
  })
  use time_of_day <- decode.field(1, {
    use hours <- decode.field(0, decode.int)
    use minutes <- decode.field(1, decode.int)
    use seconds <- decode.field(2, decode.float)

    let nanoseconds =
      seconds
      |> float.multiply(1_000_000_000.0)
      |> float.truncate
      |> int.modulo(1_000_000_000)
      |> result.unwrap(0)

    let seconds = float.truncate(seconds)
    decode.success(calendar.TimeOfDay(hours:, minutes:, seconds:, nanoseconds:))
  })
  decode.success(#(date, time_of_day))
}

pub fn cid_decoder() {
  use encoded <- decode.then(decode.string)
  case v1.from_string(encoded) {
    Ok(#(cid, _)) -> decode.success(cid)
    Error(_) -> decode.failure(dag_json.vacant_cid, "CID")
  }
}
