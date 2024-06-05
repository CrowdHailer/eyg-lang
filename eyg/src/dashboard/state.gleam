import facilities/accu_weather/client as accu_weather
import facilities/accu_weather/daily_forecast
import facilities/trafiklab/realtidsinformation_4 as rt4
import gleam/io
import gleam/javascript/promisex
import gleam/list
import gleam/option.{type Option, None}
import lustre/effect
import plinth/javascript/date.{type Date}
import plinth/javascript/global
import plinth/javascript/storage

pub type State {
  State(
    now: Date,
    accu_weather: Result(String, Nil),
    forecast: List(daily_forecast.DailyForecast),
    departures: List(#(String, String)),
    timer: Option(Int),
  )
}

pub fn init(_) {
  // let assert Ok(s) = storage.local()
  // let accu_weather_key = storage.get_item(s, "ACCU_WEATHER_KEY")
  // Committed to source deliberatly I will rely on rate limiting and mint a new one when needed
  let accu_weather_key = Ok("IU5BBrAzQkxuDQxXrzRDwgE1j8TguZco")
  let state = State(date.now(), accu_weather_key, [], [], None)

  let tasks = case accu_weather_key {
    Error(Nil) -> []
    Ok(accu_weather_key) -> [
      effect.from(fn(dispatch) {
        let task =
          accu_weather.five_day_forecast(
            accu_weather_key,
            accu_weather.stockholm_key,
          )
        use resolved <- promisex.aside(task)
        let assert Ok(data) = resolved
        dispatch(
          Wrap(fn(state) {
            let State(now: now, ..) = state
            let state = State(..state, forecast: data)
            #(state, effect.none())
          }),
        )
      }),
    ]
  }
  let tasks = [effect.from(watch_time), effect.from(fetch_departures), ..tasks]

  #(state, effect.batch(tasks))
}

pub type Wrap {
  Wrap(fn(State) -> #(State, effect.Effect(Wrap)))
}

pub fn update(state, msg) {
  let Wrap(msg) = msg
  msg(state)
}

// tasks

fn watch_time(dispatch) {
  global.set_timeout(1000, fn() {
    dispatch(
      Wrap(fn(state) {
        let state = State(..state, now: date.now())
        #(state, effect.from(watch_time))
      }),
    )
  })
  Nil
}

fn fetch_departures(dispatch) {
  use data <- promisex.aside(rt4.departures(
    "b8aa9e4c5e9741ca87f4371c93d0c4f6",
    rt4.eyvind_johnsons_gata,
    120,
  ))
  dispatch(
    Wrap(fn(state) {
      let state = case data {
        Ok(buses) -> {
          let to_town =
            list.filter(buses, fn(b: rt4.BusDeparture) {
              b.journey_direction == 1
            })
          let departures =
            list.map(to_town, fn(b: rt4.BusDeparture) {
              #(b.destination, b.display)
            })
          State(..state, departures: departures)
        }
        Error(reason) -> {
          io.debug(reason)
          state
        }
      }
      #(
        state,
        effect.from(fn(dispatch) {
          global.set_timeout(60_000, fn() { fetch_departures(dispatch) })
          Nil
        }),
      )
    }),
  )
}
