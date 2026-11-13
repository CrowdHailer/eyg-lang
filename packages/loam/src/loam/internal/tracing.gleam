//// Host-owned tracing state, passed explicitly through each run's continuations.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import loam/internal/chrome_trace
import otel
import otel/clock
import otel/span
import simplifile

pub opaque type Context {
  Off
  Recording(Recorder)
}

type Frame {
  Frame(span: otel.Span, children_ns: Int, effect_ns: Int)
}

type Recorder {
  Recorder(
    exporter: otel.Exporter,
    trace_id: String,
    stack: List(Frame),
    completed: List(otel.Span),
    pending: Int,
    file: Option(String),
    local: List(otel.Span),
    profile: Bool,
  )
}

pub fn new() -> Context {
  configured(otel.environment())
}

pub fn configured(env: List(#(String, String))) -> Context {
  let exporter =
    otel.configure(env, "eyg", "eyg.loam", [#("eyg.trace.mode", "effects")])
  let file = case otel.env_value(env, "EYG_PROFILE_FILE", "") {
    "" -> None
    path -> Some(path)
  }
  case exporter.disabled || { !otel.enabled(exporter) && file == None } {
    True -> Off
    False ->
      start_span(
        Recording(Recorder(
          exporter,
          otel.trace_id(),
          [],
          [],
          0,
          file,
          [],
          False,
        )),
        "eyg.run",
        [],
      )
  }
}

pub fn start_span(context, name, attributes) -> Context {
  case context {
    Off -> Off
    Recording(recorder) -> {
      let recorder = case
        !recorder.profile && list.contains(attributes, #("eyg.profile", "true"))
      {
        False -> recorder
        True ->
          Recorder(
            ..recorder,
            profile: True,
            exporter: otel.Exporter(..recorder.exporter, attributes: [
              #("eyg.trace.mode", span.Text("profile")),
            ]),
            stack: list.map(recorder.stack, fn(frame) {
              case frame.span.parent_id {
                Some(_) -> frame
                None ->
                  Frame(
                    ..frame,
                    span: span.Span(..frame.span, attributes: [
                      #("eyg.profile", span.Text("true")),
                      ..frame.span.attributes
                    ]),
                  )
              }
            }),
          )
      }
      let parent = case recorder.stack {
        [] -> None
        [frame, ..] -> Some(frame.span.span_id)
      }
      let span = otel.start_span(recorder.trace_id, parent, name, attributes)
      Recording(
        Recorder(..recorder, stack: [Frame(span, 0, 0), ..recorder.stack]),
      )
    }
  }
}

fn close(recorder: Recorder, error: Option(String)) -> Recorder {
  case recorder.stack {
    [] -> recorder
    [frame, ..rest] -> {
      let span = otel.end_span(frame.span, error)
      let elapsed = clock.difference(span.ended, span.started)
      let effect_ns = case
        list.contains(span.attributes, #(
          "eyg.profile.kind",
          span.Text("effect"),
        ))
      {
        True -> elapsed
        False -> frame.effect_ns
      }
      let span = case recorder.profile {
        False -> span
        True ->
          span.Span(
            ..span,
            attributes: list.append(span.attributes, [
              #(
                "eyg.profile.self_ns",
                span.Integer(int.max(0, elapsed - frame.children_ns)),
              ),
              #("eyg.profile.effect_ns", span.Integer(int.max(0, effect_ns))),
              #(
                "eyg.profile.active_ns",
                span.Integer(int.max(0, elapsed - effect_ns)),
              ),
            ]),
          )
      }
      let stack = case rest {
        [] -> []
        [parent, ..rest] -> [
          Frame(
            ..parent,
            children_ns: parent.children_ns + elapsed,
            effect_ns: parent.effect_ns + effect_ns,
          ),
          ..rest
        ]
      }
      Recorder(
        ..recorder,
        stack:,
        completed: [span, ..recorder.completed],
        pending: recorder.pending + 1,
        local: case recorder.file {
          None -> []
          Some(_) -> [span, ..recorder.local]
        },
      )
    }
  }
}

pub fn end_span(context: Context, error: Option(String)) -> Promise(Context) {
  case context {
    Off -> promise.resolve(Off)
    Recording(recorder) -> {
      let recorder = close(recorder, error)
      case !recorder.profile && recorder.pending >= otel.batch_size {
        False -> promise.resolve(Recording(recorder))
        True -> {
          use exporter <- promise.map(otel.export_spans(
            recorder.exporter,
            list.reverse(recorder.completed),
          ))
          Recording(Recorder(..recorder, exporter:, completed: [], pending: 0))
        }
      }
    }
  }
}

fn close_all(recorder: Recorder, error) {
  case recorder.stack {
    [] -> recorder
    _ -> close_all(close(recorder, error), error)
  }
}

/// Exit and exceptions close every open span before exporting.
pub fn finish(context: Context, error: Option(String)) -> Promise(Nil) {
  case context {
    Off -> promise.resolve(Nil)
    Recording(recorder) -> {
      let recorder = close_all(recorder, error)
      let exporter = case recorder.file {
        None -> recorder.exporter
        Some(file) -> {
          let output =
            chrome_trace.encode(recorder.local, recorder.exporter.service)
            |> json.to_string
          case simplifile.write(file, output <> "\n") {
            Ok(_) -> recorder.exporter
            Error(reason) ->
              otel.warn(
                recorder.exporter,
                "profile output failed: " <> simplifile.describe_error(reason),
              )
          }
        }
      }
      use _ <- promise.map(otel.export_spans(
        exporter,
        list.reverse(recorder.completed),
      ))
      Nil
    }
  }
}
