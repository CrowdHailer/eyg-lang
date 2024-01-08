import gleam/float
import gleam/int
import gleam/list
import plinth/javascript/date
import dashboard/state.{State}
import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{button, div, form, iframe, input, p, span}
import facilities/accu_weather/daily_forecast.{DailyForecast}

fn coerce_time(d) {
  let hours = date.hours(d)
  let #(hours, pm) = case hours > 12 {
    True -> #(hours - 12, True)
    False -> #(hours, False)
  }
  let minutes = date.minutes(d)
  #(hours, minutes, pm)
}

pub fn render(state) {
  let State(now, forecasts) = state
  let #(hours, minutes, pm) = coerce_time(now)
  let assert [today, ..later] = forecasts
  div([class("hstack bg-yellow-200")], [
    div([class("cover expand")], [
      div([class("vstack")], [
        div([class("text-9xl")], [
          text(int.to_string(hours)),
          text(":"),
          // text(" "),
          text(int.to_string(minutes)),
          text(case pm {
            True -> " pm"
            False -> " am"
          }),
        ]),
        div([class("text-3xl")], [
          text(day_of_the_week(date.day(now))),
          text(" "),
          text(int.to_string(date.date(now))),
          text(" "),
          text(month_of_the_year(date.month(now))),
        ]),
      ]),
    ]),
    div([class("vstack right")], [
      div([class("text-right my-6 mx-4")], {
        let DailyForecast(d, sunrise, sunset, low, high, day, night) = today
        let daily_forecast.Detail(precipitation, _, _) = day
        [
          div([class("text-4xl ")], [
            text("Today "),
            text(float.to_string(high)),
            text("° "),
            text(int.to_string(day.precipitation_probability)),
            text("%"),
          ]),
          div([class("text-2xl text-gray-800")], [
            text("Tonight "),
            text(float.to_string(low)),
            text("° "),
            text(int.to_string(night.precipitation_probability)),
            text("%"),
          ]),
        ]
      }),
      ..list.map(later, forecast)
    ]),
    div([class("bg-yellow-100 border-l-8 border-yellow-900 cover")], []),
  ])
}

fn day_of_the_week(count) {
  case count {
    0 -> "Sunday"
    1 -> "Monday"
    2 -> "Tuesday"
    3 -> "Wednesday"
    4 -> "Thursday"
    5 -> "Friday"
    6 -> "Saturday"
  }
}

fn month_of_the_year(count) {
  case count {
    0 -> "Sunday"
    1 -> "Monday"
    2 -> "Tuesday"
    3 -> "Wednesday"
    4 -> "Thursday"
    5 -> "Friday"
    6 -> "Saturday"
  }
}

fn forecast(f) {
  let DailyForecast(d, sunrise, sunset, low, high, day, night) = f
  let d = date.new(d)

  div([class("text-right m-4")], [
    div([class("text-lg text-gray-800")], [
      text(day_of_the_week(date.day(d))),
      text(" "),
      text(float.to_string(high)),
      text("° "),
      text(int.to_string(day.precipitation_probability)),
      text("%"),
    ]),
    div([class("text text-gray-800")], [
      text(float.to_string(low)),
      text("° "),
      text(int.to_string(night.precipitation_probability)),
      text("%"),
    ]),
  ])
  // div([class("")], [
  //   div([], [
  //     text(day_of_the_week(date.day(d))),
  //     text(" sunrise"),
  //     text(sunrise),
  //     text(" sunset"),
  //     text(sunset),
  //   ]),
  //   div([], [text("low "), text(float.to_string(low)), text("°C")]),
  //   div([], [text("high "), text(float.to_string(high)), text("°C")]),
  // ])
}
