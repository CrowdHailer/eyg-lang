import gleam/json
import gleam/option.{None, Some}
import gleeunit
import otel/clock
import otel/span
import otel/trace

pub fn main() {
  gleeunit.main()
}

pub fn clock_round_trip_test() {
  let time = clock.Time(1_700_000_000, 5)
  assert clock.encode(time) == "1700000000000000005"
  assert clock.decode("1700000000000000005") == Ok(time)
  assert clock.difference(clock.Time(2, 0), clock.Time(1, 999_999_999)) == 1
}

pub fn span_encoding_test() {
  let started = clock.Time(1, 0)
  let ended = clock.Time(1, 500)
  let ok =
    span.Span(
      "t",
      "s",
      None,
      "eyg.run",
      started,
      ended,
      [#("n", span.Integer(2))],
      None,
    )
  assert json.to_string(span.encode(ok))
    == "{\"traceId\":\"t\",\"spanId\":\"s\",\"name\":\"eyg.run\",\"kind\":1,\"startTimeUnixNano\":\"1000000000\",\"endTimeUnixNano\":\"1000000500\",\"status\":{\"code\":1},\"attributes\":[{\"key\":\"n\",\"value\":{\"intValue\":\"2\"}}]}"
  let failed = span.Span(..ok, parent_id: Some("p"), error: Some("no"))
  assert json.to_string(span.encode(failed))
    |> fn(text) { text != json.to_string(span.encode(ok)) }
}

pub fn trace_encoding_test() {
  let body = trace.encode("eyg-cloud", "eyg", [], []) |> json.to_string
  assert body
    == "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"eyg-cloud\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"eyg\"},\"spans\":[]}]}]}"
}
