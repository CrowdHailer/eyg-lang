import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import loam/internal/chrome_trace
import otel/clock
import otel/codec
import otel/span
import tracing/model
import tracing/storage
import tracing/view

pub fn main() {
  gleeunit.main()
}

pub fn captured_traces_render_with_precise_effect_time_test() {
  let assert Ok(captures) =
    storage.read("presentation/captures.json", "captures")
  list.each(captures, fn(capture) {
    assert model.verify(capture.spans) == Ok(Nil)
    let chart = view.chart(capture, False, True, None, 1)
    assert string.contains(chart, "<svg")
    assert !string.contains(chart, "NaN")
    assert !string.contains(chart, "Infinity")
  })
  let assert Ok(http) =
    list.find(captures, fn(c) { c.id == "02-http-workflow" })
  assert string.contains(view.timeline(http), "Fetch /plan")
  let assert Ok(profiles) =
    storage.read("presentation/profiles.json", "profiles")
  list.each(profiles, fn(profile) {
    assert model.verify(profile.spans) == Ok(Nil)
    let wall = model.layout(profile, False, False)
    let active = model.layout(profile, True, False)
    let assert Ok(root) = model.root(profile)
    assert wall.total - active.total
      == model.timing(root, "eyg.profile.effect_ns")
    assert list.all(active.frames, fn(f) {
      f.end >= f.start && model.kind(f.span) != "effect"
    })
    let wire = storage.payload(profile) |> json.to_string
    assert json.parse(wire, codec.spans()) == Ok(profile.spans)
  })
  assert string.contains(
    chrome_trace.encode([], "empty") |> json.to_string,
    "traceEvents",
  )
}

pub fn nested_effects_are_removed_only_once_test() {
  let root =
    span.Span(
      "trace",
      "root",
      None,
      "eyg.profile",
      clock.Time(1, 0),
      clock.Time(1, 100),
      [],
      None,
    )
  let child =
    span.Span(
      ..root,
      span_id: "effect",
      parent_id: Some("root"),
      name: "eyg.effect.outer",
      started: clock.Time(1, 20),
      ended: clock.Time(1, 70),
    )
  let nested =
    span.Span(
      ..child,
      span_id: "nested",
      parent_id: Some("effect"),
      started: clock.Time(1, 30),
      ended: clock.Time(1, 40),
    )
  let capture =
    model.Capture("test", "test", 0, "", "", "", [root, child, nested], [], 0)
  assert model.layout(capture, True, True).total == 50
}

pub fn malformed_ancestry_is_rejected_test() {
  let orphan =
    span.Span(
      "trace",
      "child",
      Some("missing"),
      "child",
      clock.Time(1, 0),
      clock.Time(1, 10),
      [],
      None,
    )
  let assert Error(_) = model.verify([orphan])
  assert view.escape("<script>\"&") == "&lt;script&gt;&quot;&amp;"
}

pub fn zero_duration_cycles_and_multiple_roots_are_rejected_test() {
  let root =
    span.Span(
      "trace",
      "root",
      None,
      "eyg.profile",
      clock.Time(1, 0),
      clock.Time(1, 10),
      [],
      None,
    )
  let cycle =
    span.Span(
      ..root,
      span_id: "cycle",
      parent_id: Some("cycle"),
      ended: clock.Time(1, 0),
    )
  assert model.verify([root, cycle]) == Error("cyclic span ancestry")
  let other = span.Span(..root, span_id: "other")
  assert model.verify([root, other])
    == Error("a capture must have one root span")
}

pub fn span_identifiers_are_escaped_in_html_attributes_test() {
  let root =
    span.Span(
      "trace",
      "a\" onclick=\"alert(1)",
      None,
      "eyg.profile",
      clock.Time(1, 0),
      clock.Time(1, 10),
      [],
      None,
    )
  let capture = model.Capture("escape", "<title>", 0, "", "", "", [root], [], 0)
  let svg = view.chart(capture, False, True, None, 1)
  assert string.contains(svg, "data-frame=\"a&quot; onclick=&quot;alert(1)\"")
  assert !string.contains(svg, " onclick=\"alert")
}
