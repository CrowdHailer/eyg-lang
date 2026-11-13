//// Pages to browse what the mock has received, in the style of the EYG website.

import glasshouse_mock/langfuse.{type Observation, type Trace}
import glasshouse_mock/model
import glasshouse_mock/neon
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp

const style =
  "
body { font-family: ui-sans-serif, system-ui, sans-serif; margin: 0; background: #daf5f0; color: #111; }
header { background: #fff; border-bottom: 2px solid #000; padding: 12px 24px; display: flex; gap: 24px; align-items: baseline; }
header strong { font-size: 1.25rem; }
header a { color: #000; }
main { max-width: 1100px; margin: 0 auto; padding: 24px; }
.card { background: #fff; border: 2px solid #000; box-shadow: 4px 4px 0 #000; padding: 16px; margin-bottom: 16px; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid #ccc; vertical-align: top; }
th { border-bottom: 2px solid #000; }
.badge { display: inline-block; border: 2px solid #000; padding: 0 6px; font-size: 0.75rem; font-weight: bold; margin-right: 6px; }
.GENERATION { background: #c4a1ff; } .SPAN { background: #87ceeb; } .EVENT { background: #fdfd96; } .TOOL { background: #90ee90; }
.ERROR { background: #ff6b6b; }
pre { white-space: pre-wrap; word-break: break-word; background: #f6f6f6; border: 1px solid #ccc; padding: 8px; margin: 4px 0; max-height: 240px; overflow: auto; font-size: 0.8rem; }
.muted { color: #555; font-size: 0.85rem; }
.observation { border-left: 2px solid #000; padding-left: 12px; margin: 8px 0 8px 8px; }
details summary { cursor: pointer; }
"

pub fn escape(text: String) -> String {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
}

fn page(title, body) {
  "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>"
  <> escape(title)
  <> "</title><style>"
  <> style
  <> "</style></head><body><header><strong>Glasshouse mock</strong>"
  <> "<a href=\"/\">Langfuse traces</a><a href=\"/neon\">Neon database</a><a href=\"/model\">Model script</a></header><main>"
  <> body
  <> "</main></body></html>"
}

fn time(milliseconds) {
  timestamp.from_unix_seconds_and_nanoseconds(
    milliseconds / 1000,
    { milliseconds % 1000 } * 1_000_000,
  )
  |> timestamp.to_rfc3339(calendar.utc_offset)
}

pub fn traces(store: langfuse.Store) -> String {
  let rows =
    langfuse.traces(store)
    |> list.map(fn(trace) {
      "<tr><td><a href=\"/trace/"
      <> trace.id
      <> "\">"
      <> escape(trace.name)
      <> "</a></td><td>"
      <> escape(trace.session)
      <> "</td><td>"
      <> time(trace.started)
      <> "</td><td>"
      <> int.to_string(list.length(trace.observations))
      <> "</td><td>"
      <> int.to_string(langfuse.tokens(trace))
      <> "</td></tr>"
    })
  let body = case rows {
    [] ->
      "<div class=\"card\"><p>No traces yet.</p><p class=\"muted\">Upload a session with <code>eyg upload trace.json</code>, with <code>LANGFUSE_HOST</code> set to this server.</p></div>"
    rows ->
      "<div class=\"card\"><table><tr><th>Trace</th><th>Session</th><th>Started</th><th>Observations</th><th>Tokens</th></tr>"
      <> string.concat(rows)
      <> "</table></div>"
  }
  page("Traces", "<h1>Traces</h1>" <> body)
}

pub fn trace(trace: Trace) -> String {
  let roots = list.filter(trace.observations, fn(o) { o.parent == None })
  let metadata = case trace.metadata {
    [] -> ""
    pairs -> pairs_table(pairs)
  }
  page(
    trace.name,
    "<h1>"
      <> escape(trace.name)
      <> "</h1><div class=\"card\"><p class=\"muted\">Trace "
      <> trace.id
      <> " · session "
      <> escape(trace.session)
      <> " · "
      <> time(trace.started)
      <> " · "
      <> int.to_string(langfuse.tokens(trace))
      <> " tokens</p>"
      <> metadata
      <> section("Input", trace.input)
      <> section("Output", trace.output)
      <> "</div><div class=\"card\">"
      <> string.concat(list.map(roots, observation(_, trace.observations)))
      <> "</div>",
  )
}

fn observation(node: Observation, all: List(Observation)) -> String {
  let children = list.filter(all, fn(o) { o.parent == Some(node.id) })
  let type_ = string.uppercase(node.type_)
  let level = case node.error {
    Some(reason) ->
      "<span class=\"badge ERROR\">ERROR</span>"
      <> "<span class=\"muted\">"
      <> escape(reason)
      <> "</span>"
    None -> ""
  }
  let usage = case node.input_tokens + node.output_tokens {
    0 -> ""
    _ ->
      " · "
      <> int.to_string(node.input_tokens)
      <> " → "
      <> int.to_string(node.output_tokens)
      <> " tokens"
  }
  let llm = case node.model {
    "" -> ""
    name -> " · " <> escape(name)
  }
  "<div class=\"observation\"><details"
  <> case type_ {
    "EVENT" -> ""
    _ -> " open"
  }
  <> "><summary><span class=\"badge "
  <> type_
  <> "\">"
  <> type_
  <> "</span><strong>"
  <> escape(node.name)
  <> "</strong> <span class=\"muted\">"
  <> int.to_string(node.ended - node.started)
  <> "ms"
  <> llm
  <> usage
  <> "</span> "
  <> level
  <> "</summary>"
  <> pairs_table(node.metadata)
  <> section("Input", node.input)
  <> section("Output", node.output)
  <> string.concat(list.map(children, observation(_, all)))
  <> "</details></div>"
}

fn section(label, text) {
  case text {
    "" -> ""
    text ->
      "<div class=\"muted\">"
      <> label
      <> "</div><pre>"
      <> escape(text)
      <> "</pre>"
  }
}

fn pairs_table(pairs) {
  case pairs {
    [] -> ""
    pairs ->
      "<table>"
      <> list.map(pairs, fn(pair) {
        let #(key, value) = pair
        "<tr><th>"
        <> escape(key)
        <> "</th><td>"
        <> escape(value)
        <> "</td></tr>"
      })
      |> string.concat
      <> "</table>"
  }
}

pub fn database(history: neon.History) -> String {
  let tables =
    neon.current(history)
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(entry) {
      let #(name, neon.Table(columns:, rows:)) = entry
      "<div class=\"card\"><h2>"
      <> escape(name)
      <> "</h2><table><tr>"
      <> string.concat(
        list.map(columns, fn(c) { "<th>" <> escape(c) <> "</th>" }),
      )
      <> "</tr>"
      <> string.concat(
        list.map(rows, fn(row) {
          "<tr>"
          <> string.concat(
            list.map(row, fn(cell) {
              "<td>" <> escape(option.unwrap(cell, "NULL")) <> "</td>"
            }),
          )
          <> "</tr>"
        }),
      )
      <> "</table></div>"
    })
  let changes =
    list.map(history, fn(state) { "<li>" <> time(state.0) <> "</li>" })
  page(
    "Neon database",
    "<h1>Neon database</h1>"
      <> case tables {
      [] -> "<div class=\"card\"><p>The database is empty.</p></div>"
      tables -> string.concat(tables)
    }
      <> "<div class=\"card\"><h2>History</h2><p class=\"muted\">Queries at a point in time read the state from that time.</p><ul>"
      <> string.concat(changes)
      <> "</ul></div>",
  )
}

pub fn script(rules: List(model.Rule)) -> String {
  let rules =
    list.map(rules, fn(rule) {
      let model.Rule(prompt:, system:, steps:) = rule
      "<div class=\"card\"><p><strong>When the prompt contains</strong> "
      <> escape(prompt)
      <> case system {
        "" -> ""
        system ->
          " <strong>and the system prompt contains</strong> " <> escape(system)
      }
      <> "</p>"
      <> string.concat(
        list.map(steps, fn(step) {
          case step {
            model.Code(code) ->
              "<span class=\"badge TOOL\">run</span><pre>"
              <> escape(code)
              <> "</pre>"
            model.Answer(text) ->
              "<span class=\"badge GENERATION\">answer</span><pre>"
              <> escape(text)
              <> "</pre>"
          }
        }),
      )
      <> "</div>"
    })
  page(
    "Model script",
    "<h1>Model script</h1>"
      <> case rules {
      [] ->
        "<div class=\"card\"><p>No script loaded, set <code>MOCK_SCRIPT</code> to a script file.</p></div>"
      rules -> string.concat(rules)
    },
  )
}

pub fn not_found() -> String {
  page("Not found", "<h1>Not found</h1>")
}
