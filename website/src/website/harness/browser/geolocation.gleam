import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/float
import gleam/javascript/promise
import gleam/result
import plinth/browser/geolocation.{GeolocationPosition}

pub type Reply =
  Result(geolocation.GeolocationPosition, String)

pub const l = "Geo"

pub const lift = t.unit

pub fn lower() {
  t.result(
    t.record([
      #("latitude", t.Integer),
      #("longitude", t.Integer),
      #("altitude", t.option(t.Integer)),
      #("accuracy", t.Integer),
      #("altitude_accuracy", t.option(t.Integer)),
      #("heading", t.option(t.Integer)),
      #("speed", t.option(t.Integer)),
      #("timestamp", t.Integer),
    ]),
    t.String,
  )
}

pub fn type_() {
  #(l, #(lift, lower()))
}

pub fn blocking(lift) {
  use Nil <- result.map(cast.as_unit(lift, Nil))
  promise.map(do(), result_to_eyg)
}

pub fn preflight(lift) {
  use Nil <- result.map(cast.as_unit(lift, Nil))
  fn() { promise.map(do(), result_to_eyg) }
}

pub fn handle(lift) {
  use p <- result.map(blocking(lift))
  v.Promise(p)
}

pub fn do() {
  geolocation.current_position()
}

pub fn position_to_eyg(position) {
  let GeolocationPosition(
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
    accuracy: accuracy,
    altitude_accuracy: altitude_accuracy,
    heading: heading,
    speed: speed,
    timestamp: timestamp,
  ) = position
  v.Record(
    dict.from_list([
      #("latitude", v.Integer(float.truncate(latitude))),
      #("longitude", v.Integer(float.truncate(longitude))),
      #("altitude", v.option(altitude, fn(x) { v.Integer(float.truncate(x)) })),
      #("accuracy", v.Integer(float.truncate(accuracy))),
      #(
        "altitude_accuracy",
        v.option(altitude_accuracy, fn(x) { v.Integer(float.truncate(x)) }),
      ),
      #("heading", v.option(heading, fn(x) { v.Integer(float.truncate(x)) })),
      #("speed", v.option(speed, fn(x) { v.Integer(float.truncate(x)) })),
      #("timestamp", v.Integer(float.truncate(timestamp))),
    ]),
  )
}

pub fn result_to_eyg(result) {
  case result {
    Ok(position) -> v.ok(position_to_eyg(position))
    Error(reason) -> v.error(v.String(reason))
  }
}
