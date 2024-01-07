import gleam/float
import gleam/int
import gleam/list
import dashboard/state.{State}
import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{button, div, form, iframe, input, p, span}
import facilities/accu_weather/daily_forecast.{DailyForecast}

pub fn render(state) {
  let State(#(hours, minutes, pm), forecasts) = state

  div([class("p-6 ")], [
    span([class("text-6xl")], [
      text(int.to_string(hours)),
      text(":"),
      text(int.to_string(minutes)),
      text(case pm {
        True -> "pm"
        False -> "am"
      }),
    ]),
    ..list.map(forecasts, forecast)
  ])
}

fn forecast(f) {
  let DailyForecast(date, sunrise, sunset, low, high, day, night) = f
  div([class("border")], [
    div([], [
      text(date),
      text(" sunrise"),
      text(sunrise),
      text(" sunset"),
      text(sunset),
    ]),
    div([], [text("low "), text(float.to_string(low)), text("°C")]),
    div([], [text("high "), text(float.to_string(high)), text("°C")]),
  ])
}
