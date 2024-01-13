import gleam/io
import gleam/float
import gleam/int
import gleam/list
import gleam/javascript/promise
import plinth/javascript/date
import plinth/browser/document
import plinth/browser/element as dom_element
import plinth/browser/window
import plinth/javascript/storage
import lustre/attribute.{class, id}
import lustre/element.{text}
import lustre/element/html.{button, div, form, iframe, input, p, span}
import lustre/effect
import lustre/event.{on_click}
import facilities/accu_weather/daily_forecast.{DailyForecast}
import dashboard/state.{State, Wrap}

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
  let State(now, accu_weather_key, forecasts) = state
  // save sets value in storage and then reloads the page
  case accu_weather_key {
    Error(Nil) ->
      div([id("root"), class("vstack")], [
        div([class("bg-gray-400 border rounded")], [
          div([class("p-4")], [
            div([], [text("input key")]),
            div([], [input([id("key-input")])]),
            div([], [
              button(
                [
                  on_click(
                    Wrap(fn(state) {
                      io.debug("save")
                      let assert Ok(input) =
                        document.query_selector("#key-input")
                      let assert Ok(value) = dom_element.value(input)
                      io.debug(value)
                      let assert Ok(s) = storage.local()
                      let assert Ok(Nil) =
                        storage.set_item(s, "ACCU_WEATHER_KEY", value)
                      // d(Wrap(todo))
                      window.reload()
                      #(state, effect.none())
                    }),
                  ),
                ],
                [text("save")],
              ),
            ]),
          ]),
        ]),
      ])
    Ok(_) -> display(now, forecasts)
  }
}

fn display(now, forecasts) {
  let #(hours, minutes, pm) = coerce_time(now)
  div([id("root"), class("hstack bg-yellow-200")], [
    div([class("cover expand")], [
      div([class("vstack")], [
        div(
          [
            class("text-9xl"),
            on_click(
              Wrap(fn(state) {
                let assert Ok(root) = document.query_selector("#root")
                promise.map(dom_element.request_fullscreen(root), fn(r) {
                  io.debug(r)
                })
                promise.map(window.request_wake_lock(), io.debug)
                io.debug("noo")
                #(state, effect.none())
              }),
            ),
          ],
          [
            text(int.to_string(hours)),
            text(":"),
            // text(" "),
            text(int.to_string(minutes)),
            text(case pm {
              True -> " pm"
              False -> " am"
            }),
          ],
        ),
        div([class("text-3xl")], [
          text(day_of_the_week(date.day(now))),
          text(" "),
          text(int.to_string(date.date(now))),
          text(" "),
          text(month_of_the_year(date.month(now))),
        ]),
      ]),
    ]),
    case forecasts {
      [today, ..later] ->
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
        ])
      _ -> div([], [text("no forecast")])
    },
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
    0 -> "January"
    1 -> "Feburary"
    2 -> "March"
    3 -> "April"
    4 -> "May"
    5 -> "June"
    6 -> "July"
    7 -> "August"
    8 -> "September"
    9 -> "October"
    10 -> "November"
    11 -> "December"
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
