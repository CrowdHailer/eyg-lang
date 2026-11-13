//// The OTLP/HTTP JSON subset produced by this project, also read by its tools.

import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import otel/clock
import otel/span

fn time() -> decode.Decoder(clock.Time) {
  use value <- decode.then(decode.string)
  case clock.decode(value) {
    Ok(time) -> decode.success(time)
    Error(_) -> decode.failure(clock.Time(0, 0), "epoch nanoseconds")
  }
}

fn attribute_value() -> decode.Decoder(span.Attribute) {
  // Delay construction until decoding, allowing nested AnyValue arrays.
  use _ <- decode.then(decode.dynamic)
  let text = {
    use value <- decode.field("stringValue", decode.string)
    decode.success(span.Text(value))
  }
  let integer = {
    use value <- decode.field(
      "intValue",
      decode.one_of(decode.int, [
        {
          use value <- decode.then(decode.string)
          case int.parse(value) {
            Ok(value) -> decode.success(value)
            Error(_) -> decode.failure(0, "integer")
          }
        },
      ]),
    )
    decode.success(span.Integer(value))
  }
  let boolean =
    decode.field("boolValue", decode.bool, fn(value) {
      decode.success(span.Boolean(value))
    })
  let real =
    decode.field("doubleValue", decode.float, fn(value) {
      decode.success(span.Real(value))
    })
  let array =
    decode.field(
      "arrayValue",
      {
        use values <- decode.field("values", decode.list(attribute_value()))
        decode.success(span.Array(values))
      },
      decode.success,
    )
  decode.one_of(text, [integer, boolean, real, array])
}

fn attribute() -> decode.Decoder(#(String, span.Attribute)) {
  use key <- decode.field("key", decode.string)
  use value <- decode.field("value", attribute_value())
  decode.success(#(key, value))
}

pub fn span() -> decode.Decoder(span.Span) {
  use trace_id <- decode.field("traceId", decode.string)
  use span_id <- decode.field("spanId", decode.string)
  use parent_id <- decode.optional_field(
    "parentSpanId",
    None,
    decode.map(decode.string, Some),
  )
  use name <- decode.field("name", decode.string)
  use started <- decode.field("startTimeUnixNano", time())
  use ended <- decode.field("endTimeUnixNano", time())
  use attributes <- decode.optional_field(
    "attributes",
    [],
    decode.list(attribute()),
  )
  use error <- decode.optional_field("status", None, {
    use code <- decode.optional_field("code", 0, decode.int)
    use message <- decode.optional_field("message", "", decode.string)
    decode.success(case code {
      2 -> Some(message)
      _ -> None
    })
  })
  decode.success(span.Span(
    trace_id,
    span_id,
    parent_id,
    name,
    started,
    ended,
    attributes,
    error,
  ))
}

pub fn spans() -> decode.Decoder(List(span.Span)) {
  let scope = {
    use spans <- decode.field("spans", decode.list(span()))
    decode.success(spans)
  }
  let resource = {
    use scopes <- decode.field("scopeSpans", decode.list(scope))
    decode.success(list.flatten(scopes))
  }
  use resources <- decode.field("resourceSpans", decode.list(resource))
  decode.success(list.flatten(resources))
}
