//// Offline presentation and browser bundle generation; all layout is Gleam.

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import loam/internal/chrome_trace
import otel/clock
import simplifile
import tracing/host
import tracing/model
import tracing/storage
import tracing/view

fn page(title, body, extra) {
  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>"
  <> view.escape(title)
  <> "</title><style>"
  <> view.css
  <> "</style></head><body>"
  <> body
  <> extra
  <> "</body></html>"
}

fn slide(title, body) {
  "<section class=\"slide\"><h2>"
  <> view.escape(title)
  <> "</h2>"
  <> body
  <> "</section>"
}

fn code(source) {
  "<pre><code>" <> view.escape(source) <> "</code></pre>"
}

pub fn presentation(
  captures: List(model.Capture),
  profiles: List(model.Capture),
) -> String {
  let opening = [
    slide(
      "Start with explicit tracing",
      "<p>Describe meaningful host operations with lazy, nested spans.</p>"
        <> code(
        "system.span(\"load configuration\", [],\n  fn() { system.env(\"EYG_ORIGIN\") },\n  fn(_) { None },\n)",
      )
        <> "<p>Gleam owns trace state, OTLP encoding, batching, and errors. Plinthx binds only native APIs.</p>",
    ),
    slide(
      "Then observe evaluation and effects",
      code("eyg.run\n  eyg.eval\n    eyg.effect.Fetch\n    eyg.effect.Sleep")
        <> "<p>Parent width includes child work and waiting. These are instrumented wall-clock spans, not sampled CPU usage.</p><p>OTLP/HTTP → Jaeger or any compatible collector.</p>",
    ),
  ]
  let examples =
    list.map(captures, fn(capture) {
      let trace_id = case model.root(capture) {
        Ok(root) -> root.trace_id
        Error(_) -> ""
      }
      slide(
        capture.title,
        "<div class=\"chart\">"
          <> view.chart(capture, False, True, None, 1)
          <> "</div>"
          <> code(capture.source)
          <> "<p>Exit "
          <> int.to_string(capture.exit)
          <> " · trace "
          <> trace_id
          <> "</p>",
      )
    })
  let timeline = case
    list.find(captures, fn(c) { c.id == "02-http-workflow" })
  {
    Error(_) -> []
    Ok(http) -> [
      slide(
        "Read the HTTP workflow as a timeline",
        view.timeline(http)
          <> "<p>Routes come from the fixture server's request log. Delays are deliberate local fixtures, not model benchmarks.</p>",
      ),
    ]
  }
  let profiling =
    list.flat_map(profiles, fn(profile) {
      [
        slide(
          profile.title <> " · elapsed",
          "<div class=\"chart\">"
            <> view.chart(profile, False, False, None, 1)
            <> "</div><p>Curried applications and callbacks retain definition names. Continuation re-entry records new segments with the same logical call ID.</p>",
        ),
        slide(
          profile.title <> " · evaluation",
          "<div class=\"chart\">"
            <> view.chart(profile, True, False, None, 1)
            <> "</div><p>Host-effect intervals are removed once. Interpreter, GC, scheduling, and instrumentation overhead remain.</p><p><a href=\"profile.html\">Open interactive performance view</a></p>",
        ),
      ]
    })
  let ending = [
    slide(
      "Errors describe execution",
      "<p>A failed ReadFile can be recovered by EYG. An unhandled Abort fails the evaluation. A returned HTTP 503 is still a successful Fetch transport response.</p><p>Execution evidence is not a task-quality score, and trace storage is not a replay log.</p>",
    ),
    slide(
      "Run your own recording",
      code(
        "# From packages/tracing\ngleam run -- capture\ngleam run -- profile-capture\ngleam run -- export",
      )
        <> "<p><a href=\"profile.html\">Performance view</a> · <a href=\"http://localhost:16686\">Jaeger</a> · <a href=\"../../../guides/tracing.md\">Tracing guide</a></p>",
    ),
  ]
  page(
    "OpenTelemetry in EYG",
    "<main><h1>Effects, made visible.</h1>"
      <> string.concat(
      list.flatten([opening, examples, timeline, profiling, ending]),
    )
      <> "</main>",
    "",
  )
}

pub fn viewer(profiles: List(model.Capture)) -> String {
  let options =
    list.index_map(profiles, fn(capture, index) {
      "<option value=\""
      <> int.to_string(index)
      <> "\">"
      <> view.escape(capture.title)
      <> "</option>"
    })
    |> string.concat
  let body =
    "<div id=\"viewer\"><header><h1>EYG evaluation performance</h1><p>Every function on an execution timeline. Same OTLP spans as Jaeger.</p></header><nav><label>Recording <select id=\"recording\">"
    <> options
    <> "</select></label><label>Clock <select id=\"clock\"><option value=\"wall\">Elapsed</option><option value=\"active\">Host effects removed</option></select></label><label><input id=\"intrinsics\" type=\"checkbox\"> Show intrinsics</label><label>Zoom <input id=\"zoom\" type=\"range\" min=\"1\" max=\"8\" value=\"1\"></label><button id=\"reset\">Reset zoom</button><a id=\"download\" download>Chrome trace JSON</a><a id=\"jaeger\" target=\"_blank\" rel=\"noreferrer\">Jaeger</a></nav><main><p id=\"stats\"></p><p>Click a frame for details; double-click to focus. Switch clocks to collapse host-effect intervals.</p><div id=\"chart\"></div><div class=\"columns\"><section><h2>Bottom-up self time</h2><p>Counts are unary application segments. Inclusive times overlap; self times do not.</p><div class=\"scroll\" id=\"rows\"></div></section><section id=\"detail\"></section></div><p class=\"muted\">Instrumented wall time, not sampled CPU usage. <a href=\"index.html\">Presentation</a></p></main></div>"
  let data =
    storage.collection("profiles", profiles)
    |> json.to_string
    |> string.replace("<", "\\u003c")
  page(
    "EYG evaluation performance",
    body,
    "<script id=\"recordings\" type=\"application/json\">"
      <> data
      <> "</script><script src=\"viewer.js\"></script>",
  )
}

fn summary(captures) {
  "# Measured EYG traces\n\nInstrumented wall-clock measurements, not sampled CPU usage.\n\n| Program | Elapsed ms | Spans | Exit | Trace ID |\n|---|---:|---:|---:|---|\n"
  <> string.concat(
    list.map(captures, fn(c: model.Capture) {
      let assert Ok(root) = model.root(c)
      "| "
      <> c.id
      <> " | "
      <> view.ms(clock.difference(root.ended, root.started))
      <> " | "
      <> int.to_string(list.length(c.spans))
      <> " | "
      <> int.to_string(c.exit)
      <> " | "
      <> root.trace_id
      <> " |\n"
    }),
  )
}

pub fn write(
  captures: List(model.Capture),
  profiles: List(model.Capture),
  output: String,
) -> Result(Nil, String) {
  use _ <- result.try(
    simplifile.create_directory_all(output)
    |> result.map_error(simplifile.describe_error),
  )
  use _ <- result.try(
    list.try_each(list.append(captures, profiles), fn(c) {
      use _ <- result.try(model.verify(c.spans))
      use _ <- result.try(storage.write(
        output <> "/" <> c.id <> ".svg",
        view.chart(c, False, False, None, 1),
      ))
      use _ <- result.try(storage.write_json(
        output <> "/" <> c.id <> ".otlp.json",
        storage.payload(c),
      ))
      storage.write_json(
        output <> "/" <> c.id <> ".chrome.json",
        chrome_trace.encode(c.spans, "eyg-" <> c.id),
      )
    }),
  )
  use _ <- result.try(storage.write(
    output <> "/index.html",
    presentation(captures, profiles),
  ))
  use _ <- result.try(storage.write(output <> "/profile.html", viewer(profiles)))
  use _ <- result.try(storage.write(output <> "/summary.md", summary(captures)))
  use _ <- result.try(storage.write(
    output <> "/profile-summary.md",
    summary(profiles),
  ))
  use _ <- result.try(
    case list.find(captures, fn(c) { c.id == "02-http-workflow" }) {
      Error(_) -> Ok(Nil)
      Ok(capture) ->
        storage.write(
          output <> "/timeline.html",
          page(
            "HTTP timeline",
            "<main><h1>HTTP workflow timeline</h1>"
              <> view.timeline(capture)
              <> "</main>",
            "",
          ),
        )
    },
  )
  case list.find(profiles, fn(c) { c.delay > 0 }) {
    Error(_) -> Ok(Nil)
    Ok(profile) -> {
      use _ <- result.try(storage.write(
        output <> "/profile-elapsed.svg",
        view.chart(profile, False, False, None, 1),
      ))
      storage.write(
        output <> "/profile-active.svg",
        view.chart(profile, True, False, None, 1),
      )
    }
  }
}

pub fn run(input: String, output: String) -> Promise(Result(Nil, String)) {
  let loaded = {
    use captures <- result.try(storage.read(
      input <> "/captures.json",
      "captures",
    ))
    use profiles <- result.try(
      case simplifile.is_file(input <> "/profiles.json") {
        Ok(True) -> storage.read(input <> "/profiles.json", "profiles")
        Ok(False) | Error(simplifile.Enoent) -> Ok([])
        Error(reason) -> Error(simplifile.describe_error(reason))
      },
    )
    write(captures, profiles, output)
  }
  case loaded {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(_) -> {
      // Generated browser code; the entrypoint, rendering, and interactions are Gleam.
      use result <- promise.map(
        host.command(
          [
            "bun",
            "build",
            "build/dev/javascript/tracing/tracing/viewer.mjs",
            "--target=browser",
            "--format=esm",
            "--banner=// Generated from tracing/viewer.gleam; native bindings are in plinthx.",
            "--footer=main();",
            "--outfile",
            output <> "/viewer.js",
          ],
          ".",
          [],
        ),
      )
      use built <- result.try(result)
      case built.status {
        0 -> {
          use script <- result.try(
            simplifile.read(output <> "/viewer.js")
            |> result.map_error(simplifile.describe_error),
          )
          use html <- result.try(
            simplifile.read(output <> "/profile.html")
            |> result.map_error(simplifile.describe_error),
          )
          // Inline the generated module so the viewer also works from file://.
          storage.write(
            output <> "/profile.html",
            string.join(
              string.split(html, "<script src=\"viewer.js\"></script>"),
              "<script type=\"module\">"
                <> string.replace(script, "</script", "<\\/script")
                <> "</script>",
            ),
          )
        }
        _ -> Error(built.stderr)
      }
    }
  }
}
