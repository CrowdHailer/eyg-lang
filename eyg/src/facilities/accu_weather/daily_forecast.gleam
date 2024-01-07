import gleam/dynamic
import gleam/option.{type Option}

pub type DailyForecast {
  DailyForecast(
    date: String,
    sunrise: String,
    sunset: String,
    minimum_temperature: Float,
    maximum_temperature: Float,
    day: Detail,
    night: Detail,
  )
}

pub type Detail {
  Detail(
    precipitation_probability: Int,
    wind_speed: Float,
    wind_direction: String,
  )
}

pub fn decode_daily_forcast(raw) {
  dynamic.decode7(
    DailyForecast,
    dynamic.field("Date", dynamic.string),
    dynamic.field("Sun", dynamic.field("Rise", dynamic.string)),
    dynamic.field("Sun", dynamic.field("Set", dynamic.string)),
    dynamic.field(
      "Temperature",
      dynamic.field("Minimum", dynamic.field("Value", dynamic.float)),
    ),
    dynamic.field(
      "Temperature",
      dynamic.field("Maximum", dynamic.field("Value", dynamic.float)),
    ),
    dynamic.field("Day", decode_detail),
    dynamic.field("Night", decode_detail),
  )(raw)
}

fn decode_detail(raw) {
  dynamic.decode3(
    Detail,
    dynamic.field("PrecipitationProbability", dynamic.int),
    dynamic.field(
      "Wind",
      dynamic.field("Speed", dynamic.field("Value", dynamic.float)),
    ),
    dynamic.field(
      "Wind",
      dynamic.field("Direction", dynamic.field("English", dynamic.string)),
    ),
  )(raw)
}
