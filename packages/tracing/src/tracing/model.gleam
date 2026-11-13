//// Shared immutable trace decoding and layout, used on the host and in browsers.

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import otel/clock
import otel/codec
import otel/span

pub type Capture {
  Capture(
    id: String,
    title: String,
    exit: Int,
    stdout: String,
    stderr: String,
    source: String,
    spans: List(span.Span),
    requests: List(#(String, Int)),
    delay: Int,
  )
}

pub type Frame {
  Frame(span: span.Span, start: Int, end: Int, depth: Int)
}

pub type Layout {
  Layout(total: Int, frames: List(Frame))
}

pub fn decoder() -> decode.Decoder(Capture) {
  use id <- decode.field("id", decode.string)
  use title <- decode.optional_field("title", id, decode.string)
  use exit <- decode.optional_field("exit", 0, decode.int)
  use stdout <- decode.optional_field("stdout", "", decode.string)
  use stderr <- decode.optional_field("stderr", "", decode.string)
  use source <- decode.optional_field("source", "", decode.string)
  use spans <- decode.field("otlp", codec.spans())
  use requests <- decode.optional_field(
    "requests",
    [],
    decode.list({
      use path <- decode.field("path", decode.string)
      use status <- decode.field("status", decode.int)
      decode.success(#(path, status))
    }),
  )
  use delay <- decode.optional_field("delay", 0, decode.int)
  decode.success(Capture(
    id,
    title,
    exit,
    stdout,
    stderr,
    source,
    spans,
    requests,
    delay,
  ))
}

pub fn collection(field: String) -> decode.Decoder(List(Capture)) {
  use captures <- decode.field(field, decode.list(decoder()))
  decode.success(captures)
}

pub fn attribute(value: span.Span, key: String, default: String) -> String {
  case list.key_find(value.attributes, key) {
    Ok(span.Text(value)) -> value
    Ok(span.Integer(value)) -> int.to_string(value)
    _ -> default
  }
}

pub fn timing(value: span.Span, key: String) -> Int {
  attribute(value, key, "0") |> int.parse |> result.unwrap(0)
}

pub fn kind(value: span.Span) -> String {
  attribute(
    value,
    "eyg.profile.kind",
    case string.starts_with(value.name, "eyg.effect.") {
      True -> "effect"
      False -> "root"
    },
  )
}

pub fn root(capture: Capture) -> Result(span.Span, Nil) {
  case list.find(capture.spans, fn(s) { s.name == "eyg.profile" }) {
    Ok(span) -> Ok(span)
    Error(_) -> list.find(capture.spans, fn(s) { s.parent_id == None })
  }
}

pub fn sorted(spans: List(span.Span)) {
  list.sort(spans, fn(a, b) {
    int.compare(clock.difference(a.started, b.started), 0)
  })
}

/// Merge host-effect intervals before subtracting them, so nested effects count once.
fn ranges(frames: List(Frame)) -> List(#(Int, Int)) {
  let effects = list.filter(frames, fn(frame) { kind(frame.span) == "effect" })
  list.fold(effects, [], fn(acc, frame) {
    case acc {
      [#(start, end), ..rest] if frame.start <= end -> [
        #(start, int.max(end, frame.end)),
        ..rest
      ]
      _ -> [#(frame.start, frame.end), ..acc]
    }
  })
}

fn clock(time: Int, ranges: List(#(Int, Int))) -> Int {
  time
  - list.fold(ranges, 0, fn(total, interval) {
    total + int.max(0, int.min(time, interval.1) - interval.0)
  })
}

pub fn layout(capture: Capture, active: Bool, intrinsics: Bool) -> Layout {
  case root(capture) {
    Error(_) -> Layout(0, [])
    Ok(root) -> {
      let frames =
        sorted(capture.spans)
        |> list.filter(fn(s) {
          root.name != "eyg.profile" || s.name != "eyg.run"
        })
        |> list.map(fn(s) {
          Frame(
            s,
            clock.difference(s.started, root.started),
            clock.difference(s.ended, root.started),
            0,
          )
        })
      let ranges = case active {
        True -> ranges(frames)
        False -> []
      }
      let shown =
        list.filter(frames, fn(f) {
          { intrinsics || kind(f.span) != "intrinsic" }
          && { !active || kind(f.span) != "effect" }
        })
      let visible =
        dict.from_list(list.map(shown, fn(f) { #(f.span.span_id, Nil) }))
      let parents =
        dict.from_list(
          list.map(frames, fn(f) { #(f.span.span_id, f.span.parent_id) }),
        )
      let frames =
        list.map(shown, fn(f) {
          Frame(
            ..f,
            start: clock(f.start, ranges),
            end: clock(f.end, ranges),
            depth: depth(
              f.span.parent_id,
              parents,
              visible,
              list.length(frames),
            ),
          )
        })
      Layout(clock(clock.difference(root.ended, root.started), ranges), frames)
    }
  }
}

fn depth(parent: Option(String), parents, visible, remaining) -> Int {
  case parent, remaining {
    None, _ | _, 0 -> 0
    Some(id), _ ->
      case dict.get(parents, id) {
        Error(_) -> 0
        Ok(parent) -> {
          let extra = case dict.has_key(visible, id) {
            True -> 1
            False -> 0
          }
          extra + depth(parent, parents, visible, remaining - 1)
        }
      }
  }
}

/// Verify the recording before saving or forwarding it as presentation evidence.
pub fn verify(spans: List(span.Span)) -> Result(Nil, String) {
  let by_id = dict.from_list(list.map(spans, fn(s) { #(s.span_id, s) }))
  use first <- result.try(
    list.first(spans) |> result.replace_error("missing spans"),
  )
  use _ <- result.try(
    case list.length(list.filter(spans, fn(s) { s.parent_id == None })) {
      1 -> Ok(Nil)
      _ -> Error("a capture must have one root span")
    },
  )
  case dict.size(by_id) == list.length(spans) && !list.is_empty(spans) {
    False -> Error("missing or duplicate spans")
    True ->
      list.try_each(spans, fn(s) {
        use _ <- result.try(case s.trace_id == first.trace_id {
          True -> Ok(Nil)
          False -> Error("multiple traces in one capture")
        })
        use _ <- result.try(ancestry(s.parent_id, by_id, [s.span_id]))
        case clock.difference(s.ended, s.started) >= 0, s.parent_id {
          False, _ -> Error("negative span duration: " <> s.name)
          True, None -> Ok(Nil)
          True, Some(id) ->
            case dict.get(by_id, id) {
              Error(_) -> Error("missing parent: " <> s.name)
              Ok(parent) ->
                case
                  s.trace_id == parent.trace_id
                  && clock.difference(s.started, parent.started) >= 0
                  && clock.difference(parent.ended, s.ended) >= 0
                {
                  True -> Ok(Nil)
                  False -> Error("span outside its parent: " <> s.name)
                }
            }
        }
      })
  }
}

fn ancestry(parent, by_id: dict.Dict(String, span.Span), seen) {
  case parent {
    None -> Ok(Nil)
    Some(id) ->
      case list.contains(seen, id) {
        True -> Error("cyclic span ancestry")
        False ->
          case dict.get(by_id, id) {
            Error(_) -> Error("missing parent: " <> id)
            Ok(span) -> ancestry(span.parent_id, by_id, [id, ..seen])
          }
      }
  }
}
