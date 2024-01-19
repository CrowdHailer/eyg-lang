import gleam/dynamic
import gleam/int
import gleam/result
import gleam/http
import gleam/http/request
import gleam/javascript/promise
import gleam/fetch

pub type Failure {
  FetchFailure(fetch.FetchError)
  ResponseFailure(code: Int)
  DecodeError(List(dynamic.DecodeError))
}

pub const eyvind_johnsons_gata = "1254"

pub fn try_await(p, to_error, k) {
  use resolved <- promise.await(p)
  case resolved {
    Ok(value) -> k(value)
    Error(reason) -> promise.resolve(Error(to_error(reason)))
  }
}

// https://journeyplanner.integration.sl.se/v1/typeahead.json?key=4fd47adc31654bdd9e3ad9f0acae4246&searchstring=eyvind
// https://api.sl.se/api2/realtimedeparturesV4.json?key=b8aa9e4c5e9741ca87f4371c93d0c4f6&siteid=1254&timewindow=120
pub fn departures(api_key, site_id, time_window) {
  let r =
    //   can't test locally because cors no set for use with localhost:8080
    request.new()
    |> request.set_host("tools.petersaxton.uk")
    |> request.set_path("/proxy/api.sl.se/api2/realtimedeparturesV4.json")
    |> request.set_query([
      #("key", api_key),
      #("siteid", site_id),
      #("timewindow", int.to_string(time_window)),
    ])
  use resp <- try_await(fetch.send(r), FetchFailure)
  use resp <- try_await(fetch.read_json_body(resp), FetchFailure)
  promise.resolve(case resp.status {
    200 ->
      dynamic.field("ResponseData", dynamic.field("Buses", dynamic.list(bus())))(
        resp.body,
      )
      |> result.map_error(DecodeError)

    code -> Error(ResponseFailure(code))
  })
}

pub type BusDeparture {
  BusDeparture(
    journey_direction: Int,
    destination: String,
    timetabled: String,
    expected: String,
    display: String,
  )
}

pub fn bus() {
  dynamic.decode5(
    BusDeparture,
    dynamic.field("JourneyDirection", dynamic.int),
    dynamic.field("Destination", dynamic.string),
    dynamic.field("TimeTabledDateTime", dynamic.string),
    dynamic.field("ExpectedDateTime", dynamic.string),
    dynamic.field("DisplayTime", dynamic.string),
  )
}
