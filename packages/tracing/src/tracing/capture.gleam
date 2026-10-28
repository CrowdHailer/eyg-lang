//// Run real EYG programs against local fixtures, verifying captured OTLP spans.

import gleam/int
import gleam/io
import gleam/javascript/array.{type Array}
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import otel
import otel/codec
import otel/span
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/javascript/array as native_array
import plinthx/javascript/string as native_string
import simplifile
import tracing/demo
import tracing/host
import tracing/model
import tracing/render
import tracing/storage

type Receiver {
  Receiver(server: server.Server, batches: Array(List(span.Span)))
}

type Example {
  Example(
    id: String,
    title: String,
    exit: Int,
    contains: String,
    effects: List(String),
    paths: List(String),
    delay: Int,
  )
}

fn examples(profile: Bool) {
  case profile {
    True -> [
      Example(
        "profile-compute",
        "Compute · 0 ms Sleep",
        0,
        "4456448 bytes processed",
        [],
        [],
        0,
      ),
      Example(
        "profile-slow-effect",
        "Slow effect · 120 ms Sleep",
        0,
        "4456448 bytes processed",
        [],
        [],
        120,
      ),
    ]
    False -> [
      Example(
        "01-paced-workflow",
        "See where the time goes",
        0,
        "Three stages complete",
        ["StandardOut", "Sleep", "Sleep", "Sleep", "StandardOut"],
        [],
        0,
      ),
      Example(
        "02-http-workflow",
        "Three calls. One visible bottleneck.",
        0,
        "Answer: trace the effects",
        [
          "Env",
          "Fetch",
          "StandardOut",
          "Fetch",
          "StandardOut",
          "Fetch",
          "StandardOut",
        ],
        ["/plan", "/tool", "/answer"],
        0,
      ),
      Example(
        "03-retry",
        "The shape of a retry",
        0,
        "HTTP 503; waiting",
        ["Env", "Fetch", "StandardOut", "Sleep", "Fetch", "StandardOut"],
        ["/unavailable", "/answer"],
        0,
      ),
      Example(
        "04-recovered-error",
        "A failed effect. A successful run.",
        0,
        "Recovered successfully",
        ["ReadFile", "StandardOut", "Sleep", "ReadFile", "StandardOut"],
        [],
        0,
      ),
      Example(
        "05-failed-run",
        "When the whole run fails",
        1,
        "Beginning a task",
        ["StandardOut", "Sleep"],
        [],
        0,
      ),
    ]
  }
}

fn receiver(endpoint: String) -> Result(Receiver, String) {
  use bun <- result.try(
    runtime.get() |> result.replace_error("Bun is required"),
  )
  let batches = array.from_list([])
  use server <- result.map(server.serve(
    bun,
    server.Options(0, "127.0.0.1", fn(request) {
      use body <- promise.await(fetch.request_text(request))
      let parsed = {
        use body <- result.try(body)
        use spans <- result.try(
          json.parse(body, codec.spans())
          |> result.replace_error("invalid OTLP spans"),
        )
        Ok(#(body, spans))
      }
      case parsed {
        Error(message) ->
          promise.resolve(demo.response(message, 400, "text/plain"))
        Ok(#(body, spans)) -> {
          use forwarded <- promise.map(otel.post(endpoint, body))
          case forwarded {
            Error(message) -> demo.response(message, 502, "text/plain")
            Ok(_) -> {
              let assert Ok(_) = native_array.push(batches, spans)
              demo.response("{}", 200, "application/json")
            }
          }
        }
      }
    }),
  ))
  Receiver(server, batches)
}

pub fn run(profile: Bool, output: String) -> Promise(Result(Nil, String)) {
  let endpoint =
    otel.env_value(
      otel.environment(),
      "DEMO_JAEGER_ENDPOINT",
      "http://127.0.0.1:4318/v1/traces",
    )
  case demo.start(0) {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(demo) ->
      case receiver(endpoint) {
        Error(reason) -> {
          use _ <- promise.map(server.stop(demo.server, True))
          Error(reason)
        }
        Ok(receiver) -> {
          let work =
            promise.resolve(Nil)
            |> promise.await(fn(_) {
              collect(examples(profile), demo, receiver, profile, [])
            })
            |> promise.rescue(fn(reason) {
              Error(
                native_string.from(reason) |> result.unwrap("capture failed"),
              )
            })
          use outcome <- promise.await(work)
          use _ <- promise.await(server.stop(receiver.server, True))
          use _ <- promise.await(server.stop(demo.server, True))
          case outcome {
            Error(reason) -> promise.resolve(Error(reason))
            Ok(captures) -> {
              let saved = {
                use _ <- result.try(
                  simplifile.create_directory_all(output)
                  |> result.map_error(simplifile.describe_error),
                )
                let field = case profile {
                  True -> "profiles"
                  False -> "captures"
                }
                storage.write_json(
                  output <> "/" <> field <> ".json",
                  storage.collection(field, captures),
                )
              }
              case saved {
                Error(reason) -> promise.resolve(Error(reason))
                Ok(_) -> render.run(output, output)
              }
            }
          }
        }
      }
  }
}

fn collect(
  examples: List(Example),
  demo: demo.Demo,
  receiver: Receiver,
  profile: Bool,
  acc: List(model.Capture),
) -> Promise(Result(List(model.Capture), String)) {
  case examples {
    [] -> promise.resolve(Ok(list.reverse(acc)))
    [example, ..rest] -> {
      let assert Ok(_) =
        native_array.splice(
          receiver.batches,
          0,
          array.size(receiver.batches),
          [],
        )
      let assert Ok(_) =
        native_array.splice(demo.requests, 0, array.size(demo.requests), [])
      let file = case profile {
        True -> "06-function-profile"
        False -> example.id
      }
      let command = case profile {
        True -> "profile"
        False -> "run"
      }
      use output <- promise.try_await(
        host.cli([command, "../tracing/examples/" <> file <> ".eyg"], [
          #(
            "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
            "http://127.0.0.1:"
              <> int.to_string(server.port(receiver.server))
              <> "/v1/traces",
          ),
          #("OTEL_SDK_DISABLED", "false"),
          #("OTEL_SERVICE_NAME", "eyg-" <> example.id),
          #("EYG_PROFILE_FILE", ""),
          #("EYG_DEMO_PORT", int.to_string(server.port(demo.server))),
          #("EYG_DEMO_DELAY", int.to_string(example.delay)),
        ]),
      )
      let spans =
        array.to_list(receiver.batches) |> list.flatten |> model.sorted
      let requests = array.to_list(demo.requests)
      let checked = {
        use _ <- result.try(
          case
            output.status == example.exit
            && string.contains(output.stdout, example.contains)
            && { output.status != 0 || output.stderr == "" }
          {
            True -> Ok(Nil)
            False ->
              Error(
                example.id
                <> ": unexpected CLI output: "
                <> output.stdout
                <> output.stderr,
              )
          },
        )
        use _ <- result.try(model.verify(spans))
        let assert Ok(root) = list.find(spans, fn(s) { s.name == "eyg.run" })
        use _ <- result.try(
          case { root.error == None } == { example.exit == 0 } {
            True -> Ok(Nil)
            False -> Error("wrong root status")
          },
        )
        use _ <- result.try(case profile {
          True ->
            case
              list.length(list.filter(spans, fn(s) { s.name == "foo" })) == 36
            {
              True -> Ok(Nil)
              False -> Error("missing foo applications")
            }
          False -> {
            let effects =
              list.filter(spans, fn(s) { model.kind(s) == "effect" })
            case
              list.map(effects, fn(s) { string.drop_start(s.name, 11) })
              == example.effects
              && list.map(requests, fn(r) { r.0 }) == example.paths
            {
              True -> Ok(Nil)
              False -> Error("unexpected effect or HTTP request order")
            }
          }
        })
        use source <- result.map(
          simplifile.read("examples/" <> file <> ".eyg")
          |> result.map_error(simplifile.describe_error),
        )
        model.Capture(
          example.id,
          example.title,
          output.status,
          output.stdout,
          output.stderr,
          source,
          spans,
          requests,
          example.delay,
        )
      }
      case checked {
        Error(reason) -> promise.resolve(Error(reason))
        Ok(capture) -> {
          io.println(
            example.id <> ": " <> int.to_string(list.length(spans)) <> " spans",
          )
          collect(rest, demo, receiver, profile, [capture, ..acc])
        }
      }
    }
  }
}
