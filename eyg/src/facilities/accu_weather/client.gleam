import facilities/accu_weather/daily_forecast
import gleam/dynamic
import gleam/fetch
import gleam/http
import gleam/http/request
import gleam/javascript/promise
import gleam/result
import gleam/string

pub type Failure {
  FetchFailure(fetch.FetchError)
  ResponseFailure(code: Int)
  DecodeError(List(dynamic.DecodeError))
}

pub const stockholm_key = "314929"

pub fn try_await(p, to_error, k) {
  use resolved <- promise.await(p)
  case resolved {
    Ok(value) -> k(value)
    Error(reason) -> promise.resolve(Error(to_error(reason)))
  }
}

pub fn five_day_forecast(api_key, location_key) {
  let r =
    request.new()
    |> request.set_host("dataservice.accuweather.com")
    |> request.set_path(
      string.concat(["/forecasts/v1/daily/5day/", location_key]),
    )
    |> request.set_query([
      #("apikey", api_key),
      #("metric", "true"),
      #("details", "true"),
    ])
  use resp <- try_await(fetch.send(r), FetchFailure)
  use resp <- try_await(fetch.read_json_body(resp), FetchFailure)
  promise.resolve(case resp.status {
    200 ->
      dynamic.field(
        "DailyForecasts",
        dynamic.list(daily_forecast.decode_daily_forcast),
      )(resp.body)
      |> result.map_error(DecodeError)

    code -> Error(ResponseFailure(code))
  })
}
