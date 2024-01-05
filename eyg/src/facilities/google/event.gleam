import gleam/io
import gleam/dynamic
import gleam/option.{type Option}

pub type Event {
  Event(
    summary: String,
    location: Option(String),
    start: DateOrDatetime,
    end: DateOrDatetime,
  )
}

pub type DateOrDatetime {
  Date(String)
  Datetime(String)
}

pub fn decode_event(raw) {
  io.debug(raw)
  dynamic.decode4(
    Event,
    dynamic.field("summary", dynamic.string),
    dynamic.optional_field("location", dynamic.string),
    dynamic.field("start", decode_date_or_datetime),
    dynamic.field("end", decode_date_or_datetime),
  )(raw)
}

pub fn decode_date_or_datetime(raw) {
  io.debug(raw)
  dynamic.any([
    dynamic.decode1(Date, dynamic.field("date", dynamic.string)),
    dynamic.decode1(Datetime, dynamic.field("dateTime", dynamic.string)),
  ])(raw)
}
