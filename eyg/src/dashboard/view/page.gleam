import dashboard/state.{State, Wrap}
import facilities/accu_weather/daily_forecast.{DailyForecast}
import gleam/float
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute.{class, id}
import lustre/effect
import lustre/element.{text}
import lustre/element/html.{button, div, form, hr, iframe, input, p, span}
import lustre/event.{on_click}
import plinth/browser/audio
import plinth/browser/document
import plinth/browser/element as dom_element
import plinth/browser/window
import plinth/javascript/date
import plinth/javascript/global
import plinth/javascript/storage

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
  let State(now, accu_weather_key, forecasts, buses, timer) = state
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
    Ok(_) -> display(now, forecasts, buses, timer)
  }
}

fn display(now, forecasts, buses, timer) {
  let #(hours, minutes, pm) = coerce_time(now)
  div([id("root"), class("hstack bg-yellow-200")], [
    case timer {
      None ->
        div([class("expand text-2xl")], [
          div([class("")], [
            button([on_click(Wrap(start_timer(5000)))], [text("5 seconds")]),
          ]),
          div([class("")], [
            button([on_click(Wrap(start_timer(60_000)))], [text("1 minute")]),
          ]),
          div([class("")], [
            button([on_click(Wrap(start_timer(180_000)))], [text("Porridge !!")]),
          ]),
          div([class("")], [
            button([on_click(Wrap(start_timer(5 * 60_000)))], [
              text("5 minutes"),
            ]),
          ]),
          div([class("")], [
            button([on_click(Wrap(start_timer(10 * 60_000)))], [
              text("10 minutes"),
            ]),
          ]),
          div([class("")], [
            button([on_click(Wrap(start_timer(20 * 60_000)))], [
              text("20 minutes"),
            ]),
          ]),
        ])
      Some(milliseconds) ->
        div([class("expand text-3xl")], [
          text(int.to_string(milliseconds / 1000)),
        ])
    },
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
        hr([class("w-full")]),
        div(
          [class("text-2xl")],
          list.map(buses, fn(b) {
            let #(destination, display) = b
            div([], [text(destination), text(" "), text(display)])
          }),
        ),
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

fn start_timer(milliseconds) {
  case milliseconds >= 0 {
    True -> fn(state) {
      let state = State(..state, timer: Some(milliseconds))
      #(
        state,
        effect.from(fn(d) {
          global.set_timeout(
            fn(_) { d(Wrap(start_timer(milliseconds - 100))) },
            100,
          )
        }),
      )
    }

    False -> fn(state) {
      let state = State(..state, timer: None)
      // let beep =
      //   audio.new(
      //     "data:audio/wav;base64,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qJrx4KOQjahZxWbcZgztj2c49nKmkId44S71j0c8eV9yDK6uPRzx5X18eDvjvQ6yKo9ZSS6l//8elePK/Lf//IInrOF/FvDoADYAGBMGb7FtErm5MXMlmPAJQVgWta7Zx2go+8xJ0UiCb8LHHdftWyLJE0QIAIsI+UbXu67dZMjmgDGCGl1H+vpF4NSDckSIkk7Vd+sxEhBQMRU8j/12UIRhzSaUdQ+rQU5kGeFxm+hb1oh6pWWmv3uvmReDl0UnvtapVaIzo1jZbf/pD6ElLqSX+rUmOQNpJFa/r+sa4e/pBlAABoAAAAA3CUgShLdGIxsY7AUABPRrgCABdDuQ5GC7DqPQCgbbJUAoRSUj+NIEig0YfyWUho1VBBBA//uQZB4ABZx5zfMakeAAAAmwAAAAF5F3P0w9GtAAACfAAAAAwLhMDmAYWMgVEG1U0FIGCBgXBXAtfMH10000EEEEEECUBYln03TTTdNBDZopopYvrTTdNa325mImNg3TTPV9q3pmY0xoO6bv3r00y+IDGid/9aaaZTGMuj9mpu9Mpio1dXrr5HERTZSmqU36A3CumzN/9Robv/Xx4v9ijkSRSNLQhAWumap82WRSBUqXStV/YcS+XVLnSS+WLDroqArFkMEsAS+eWmrUzrO0oEmE40RlMZ5+ODIkAyKAGUwZ3mVKmcamcJnMW26MRPgUw6j+LkhyHGVGYjSUUKNpuJUQoOIAyDvEyG8S5yfK6dhZc0Tx1KI/gviKL6qvvFs1+bWtaz58uUNnryq6kt5RzOCkPWlVqVX2a/EEBUdU1KrXLf40GoiiFXK///qpoiDXrOgqDR38JB0bw7SoL+ZB9o1RCkQjQ2CBYZKd/+VJxZRRZlqSkKiws0WFxUyCwsKiMy7hUVFhIaCrNQsKkTIsLivwKKigsj8XYlwt/WKi2N4d//uQRCSAAjURNIHpMZBGYiaQPSYyAAABLAAAAAAAACWAAAAApUF/Mg+0aohSIRobBAsMlO//Kk4soosy1JSFRYWaLC4qZBYWFRGZdwqKiwkNBVmoWFSJkWFxX4FFRQWR+LsS4W/rFRb/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////VEFHAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAU291bmRib3kuZGUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMjAwNGh0dHA6Ly93d3cuc291bmRib3kuZGUAAAAAAAAAACU=",
      //   )
      let beep = audio.new("/long-beep.m4a")
      audio.play(beep)
      #(state, effect.none())
    }
  }
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
    _ -> panic as "not a valid day of the week"
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
    _ -> panic as "not a month of the year"
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
