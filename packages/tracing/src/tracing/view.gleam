//// Pure SVG and HTML rendering, shared with the Gleam browser viewer.

import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
import otel/clock
import otel/span
import tracing/model

pub fn escape(value: String) -> String {
  value
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
}

pub fn ms(nanos: Int) -> String {
  float.to_string(
    int.to_float(float.round(int.to_float(nanos) /. 1000.0)) /. 1000.0,
  )
}

fn number(value: Float) -> String {
  float.to_string(value)
}

fn color(frame: model.Frame) -> String {
  case frame.span.error, model.kind(frame.span) {
    Some(_), _ -> "#ff7c91"
    _, "effect" -> "#ffd083"
    _, "root" -> "#a99cff"
    _, "intrinsic" -> "#7184ad"
    _, _ ->
      case frame.depth % 3 {
        0 -> "#5ce1c1"
        1 -> "#66b9ff"
        _ -> "#afadff"
      }
  }
}

pub fn chart(
  capture: model.Capture,
  active: Bool,
  intrinsics: Bool,
  focus: Option(#(Int, Int)),
  zoom: Int,
) -> String {
  let layout = model.layout(capture, active, intrinsics)
  let #(start, end) = option.unwrap(focus, #(0, layout.total))
  let range = int.max(1, end - start)
  let frames =
    list.filter(layout.frames, fn(f) { f.start >= start && f.end <= end })
  let low = list.map(frames, fn(f) { f.depth }) |> list.fold(100_000, int.min)
  let high = list.map(frames, fn(f) { f.depth }) |> list.fold(0, int.max)
  let width = 1400 * int.max(1, zoom)
  let height = 90 + int.max(1, high - low + 1) * 38
  let bars =
    list.map(frames, fn(frame) {
      let x =
        20.0
        +. int.to_float(frame.start - start)
        /. int.to_float(range)
        *. int.to_float(width - 40)
      let w =
        int.to_float(frame.end - frame.start)
        /. int.to_float(range)
        *. int.to_float(width - 40)
      let y = 40 + { frame.depth - low } * 38
      let id = escape(frame.span.span_id)
      "<g class=\"frame\" data-frame=\""
      <> id
      <> "\"><title>"
      <> escape(frame.span.name)
      <> " · "
      <> ms(frame.end - frame.start)
      <> " ms</title><rect x=\""
      <> number(x)
      <> "\" y=\""
      <> int.to_string(y)
      <> "\" width=\""
      <> number(float.max(1.0, w))
      <> "\" height=\"30\" rx=\"4\" fill=\""
      <> color(frame)
      <> "\"/>"
      <> case w >. 65.0 {
        False -> ""
        True ->
          "<clipPath id=\"clip-"
          <> id
          <> "\"><rect x=\""
          <> number(x +. 4.0)
          <> "\" y=\""
          <> int.to_string(y)
          <> "\" width=\""
          <> number(w -. 8.0)
          <> "\" height=\"30\"/></clipPath><text x=\""
          <> number(x +. 7.0)
          <> "\" y=\""
          <> int.to_string(y + 20)
          <> "\" fill=\"#0b1220\" clip-path=\"url(#clip-"
          <> id
          <> ")\">"
          <> escape(frame.span.name)
          <> "</text>"
      }
      <> "</g>"
    })
    |> string.concat
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\""
  <> int.to_string(width)
  <> "\" height=\""
  <> int.to_string(height)
  <> "\" viewBox=\"0 0 "
  <> int.to_string(width)
  <> " "
  <> int.to_string(height)
  <> "\" role=\"img\" aria-label=\"Execution flame chart\"><style>text{font:14px system-ui}.frame{cursor:pointer}.frame:hover{opacity:.8}</style><rect width=\"100%\" height=\"100%\" fill=\"#0b1220\"/><text x=\"20\" y=\"24\" fill=\"#edf3ff\">"
  <> escape(capture.title)
  <> " · "
  <> ms(range)
  <> " ms "
  <> case active {
    True -> "outside host effects"
    False -> "elapsed"
  }
  <> "</text>"
  <> bars
  <> "</svg>"
}

pub fn timeline(capture: model.Capture) -> String {
  let assert Ok(root) = model.root(capture)
  let total = int.max(1, clock.difference(root.ended, root.started))
  let effects =
    model.sorted(capture.spans)
    |> list.filter(fn(s) { model.kind(s) == "effect" })
  let #(_, rows) =
    list.map_fold(effects, capture.requests, fn(requests, s) {
      let #(label, requests) = case s.name, requests {
        "eyg.effect.Fetch", [#(path, status), ..rest] -> #(
          "Fetch " <> path <> " → " <> int.to_string(status),
          rest,
        )
        _, _ -> #(s.name, requests)
      }
      let start = clock.difference(s.started, root.started)
      let duration = clock.difference(s.ended, s.started)
      let row =
        "<tr><td>"
        <> escape(label)
        <> "</td><td>"
        <> ms(start)
        <> "</td><td>"
        <> ms(duration)
        <> "</td><td><div class=\"bar\" style=\"margin-left:"
        <> number(int.to_float(start) /. int.to_float(total) *. 100.0)
        <> "%;width:"
        <> number(int.to_float(duration) /. int.to_float(total) *. 100.0)
        <> "%\"></div></td></tr>"
      #(requests, row)
    })
  "<table><thead><tr><th>Effect</th><th>Start ms</th><th>Duration ms</th><th>Timeline</th></tr></thead><tbody>"
  <> string.concat(rows)
  <> "</tbody></table>"
}

pub fn details(s: span.Span) -> String {
  let fields = [
    #("Inclusive", ms(clock.difference(s.ended, s.started)) <> " ms"),
    #("Self", ms(model.timing(s, "eyg.profile.self_ns")) <> " ms"),
    #("Host effects", ms(model.timing(s, "eyg.profile.effect_ns")) <> " ms"),
    #("Outside effects", ms(model.timing(s, "eyg.profile.active_ns")) <> " ms"),
    #(
      "Definition",
      model.attribute(s, "code.file.path", "runtime")
        <> ":"
        <> model.attribute(s, "code.line.number", "0"),
    ),
    #("Logical call", model.attribute(s, "eyg.profile.call_id", "—")),
    #("Span ID", s.span_id),
  ]
  "<h3>"
  <> escape(s.name)
  <> "</h3><dl>"
  <> string.concat(
    list.map(fields, fn(pair) {
      "<dt>" <> pair.0 <> "</dt><dd>" <> escape(pair.1) <> "</dd>"
    }),
  )
  <> "</dl>"
}

type Row {
  Row(
    name: String,
    id: String,
    count: Int,
    self: Int,
    inclusive: Int,
    effect: Int,
  )
}

pub fn bottom_up(
  capture: model.Capture,
  sort: String,
  intrinsics: Bool,
) -> String {
  let rows =
    list.fold(capture.spans, dict.new(), fn(rows, s) {
      case
        model.kind(s) == "function"
        || { intrinsics && model.kind(s) == "intrinsic" }
      {
        False -> rows
        True -> {
          let row =
            dict.get(rows, s.name)
            |> result.unwrap(Row(s.name, s.span_id, 0, 0, 0, 0))
          dict.insert(
            rows,
            s.name,
            Row(
              ..row,
              count: row.count + 1,
              self: row.self + model.timing(s, "eyg.profile.self_ns"),
              inclusive: row.inclusive + clock.difference(s.ended, s.started),
              effect: row.effect + model.timing(s, "eyg.profile.effect_ns"),
            ),
          )
        }
      }
    })
    |> dict.values
    |> list.sort(fn(a, b) {
      case sort {
        "name" -> string.compare(a.name, b.name)
        "count" -> int.compare(b.count, a.count)
        "inclusive" -> int.compare(b.inclusive, a.inclusive)
        "effect" -> int.compare(b.effect, a.effect)
        _ -> int.compare(b.self, a.self)
      }
    })
  let header =
    list.map(
      [
        #("name", "Function"),
        #("count", "Segments"),
        #("self", "Self ms"),
        #("inclusive", "Inclusive ms"),
        #("effect", "Host effects ms"),
      ],
      fn(pair) { "<th data-sort=\"" <> pair.0 <> "\">" <> pair.1 <> "</th>" },
    )
    |> string.concat
  "<table><thead><tr>"
  <> header
  <> "</tr></thead><tbody>"
  <> string.concat(
    list.map(rows, fn(r) {
      "<tr data-frame=\""
      <> escape(r.id)
      <> "\"><td>"
      <> escape(r.name)
      <> "</td><td>"
      <> int.to_string(r.count)
      <> "</td><td>"
      <> ms(r.self)
      <> "</td><td>"
      <> ms(r.inclusive)
      <> "</td><td>"
      <> ms(r.effect)
      <> "</td></tr>"
    }),
  )
  <> "</tbody></table>"
}

pub const css =
  "*{box-sizing:border-box}body{margin:0;background:#0b1220;color:#edf3ff;font:16px system-ui}main,header,nav{padding:24px 4vw}h1{font-size:44px}h2{font-size:32px}a{color:#5ce1c1}p{line-height:1.6}pre,section{background:#121e31;border:1px solid #293b55;border-radius:12px;padding:24px;margin-bottom:24px}pre{white-space:pre-wrap}nav{display:flex;gap:20px;align-items:center;flex-wrap:wrap}select,button{background:#182840;color:#edf3ff;border:1px solid #3a4b66;border-radius:6px;padding:8px}#chart{overflow:auto}.chart svg{width:100%;height:auto}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:10px;border-bottom:1px solid #293b55}td:last-child{min-width:120px}th[data-sort],tr[data-frame]{cursor:pointer}tr[data-frame]:hover{background:#1a3046}.bar{height:18px;background:#66b9ff;min-width:2px}dt{color:#9bacc6}dd{margin:5px 0 16px;overflow-wrap:anywhere}.slide{min-height:85vh;break-after:page}.muted{color:#9bacc6}.columns{display:grid;grid-template-columns:2fr 1fr;gap:24px}.scroll{overflow:auto;max-height:500px}button{cursor:pointer}@media(max-width:800px){.columns{grid-template-columns:1fr}}@media print{@page{size:landscape;margin:10mm}body{-webkit-print-color-adjust:exact;print-color-adjust:exact}.slide{min-height:0;height:90vh}nav{display:none}}"
