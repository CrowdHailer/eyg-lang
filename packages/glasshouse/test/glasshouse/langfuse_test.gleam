import glasshouse/fixtures
import glasshouse/helpers.{sha256}
import glasshouse/langfuse
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import otel/span

pub fn trace_and_span_ids_are_hex_test() {
  let #(session, store) = fixtures.session()
  let trace = langfuse.trace_id(session, sha256)
  assert string.length(trace) == 32
  let spans = langfuse.spans(session, store, sha256)
  assert list.all(spans, fn(span) { string.length(span.id) == 16 })
  assert list.length(list.unique(list.map(spans, fn(s) { s.id })))
    == list.length(spans)
}

pub fn ids_are_stable_test() {
  let #(session, store) = fixtures.session()
  assert langfuse.spans(session, store, sha256)
    == langfuse.spans(session, store, sha256)
}

pub fn span_tree_test() {
  let #(session, store) = fixtures.session()
  let assert [root, ..rest] = langfuse.spans(session, store, sha256)
  assert root.parent == None
  assert root.name == "overlay session"
  // config + 1 effect, prompt, 2 generations, tool + 3 effects
  assert list.length(rest) == 9
  let names = list.map(rest, fn(s) { s.name })
  assert names
    == [
      "configuration", "ReadFile", "user prompt", "generation", "run",
      "ReadFile", "WriteFile", "StandardOut", "generation",
    ]
}

fn attribute(span: langfuse.Span, key) {
  list.key_find(span.attributes, key)
  |> option.from_result
  |> option.map(fn(attribute) { span.value_json(attribute) |> json.to_string })
}

pub fn generation_attributes_test() {
  let #(session, store) = fixtures.session()
  let assert Ok(generation) =
    langfuse.spans(session, store, sha256)
    |> list.find(fn(s) { s.name == "generation" })
  assert attribute(generation, "langfuse.observation.type")
    == Some("{\"stringValue\":\"generation\"}")
  assert attribute(generation, "gen_ai.request.model")
    == Some("{\"stringValue\":\"test-model\"}")
  assert attribute(generation, "gen_ai.usage.input_tokens")
    == Some("{\"intValue\":\"120\"}")
  assert attribute(generation, "gen_ai.usage.output_tokens")
    == Some("{\"intValue\":\"30\"}")
}

pub fn tool_output_is_the_result_the_agent_saw_test() {
  let #(session, store) = fixtures.session()
  let assert Ok(tool) =
    langfuse.spans(session, store, sha256)
    |> list.find(fn(s) { s.name == "run" })
  assert attribute(tool, "langfuse.observation.type")
    == Some("{\"stringValue\":\"tool\"}")
  assert attribute(tool, "langfuse.observation.output")
    == Some("{\"stringValue\":\"done\"}")
  assert attribute(tool, "langfuse.observation.metadata.effects")
    == Some("{\"intValue\":\"3\"}")
}

pub fn effects_point_at_stored_content_test() {
  let #(session, store) = fixtures.session()
  let assert Ok(tool) =
    langfuse.spans(session, store, sha256)
    |> list.find(fn(s) { s.name == "run" })
  let assert Some(files) =
    attribute(tool, "langfuse.observation.metadata.files")
  assert string.contains(files, "/project/notes.txt@baguqeera")
}

pub fn payload_is_otlp_json_test() {
  let #(session, store) = fixtures.session()
  let payload = langfuse.payload(session, store, sha256) |> json.to_string
  let span = {
    use trace <- decode.field("traceId", decode.string)
    use start <- decode.field("startTimeUnixNano", decode.string)
    decode.success(#(trace, start))
  }
  let scope = decode.field("spans", decode.list(span), decode.success)
  let resource = decode.field("scopeSpans", decode.list(scope), decode.success)
  let decoder =
    decode.field("resourceSpans", decode.list(resource), decode.success)
  let assert Ok([[spans]]) = json.parse(payload, decoder)
  let assert [#(trace, start), ..] = spans
  assert trace == langfuse.trace_id(session, sha256)
  assert start == "1000000000"
}

pub fn request_test() {
  let assert Ok(request) =
    langfuse.request("http://localhost:3000", "pk-lf-1", "sk-lf-2", json.null())
  assert request.method == http.Post
  assert request.host == "localhost"
  assert request.port == Some(3000)
  assert request.path == "/api/public/otel/v1/traces"
  let assert Ok(expected) = bit_array.base64_decode("cGstbGYtMTpzay1sZi0y")
  assert expected == <<"pk-lf-1:sk-lf-2">>
  assert list.key_find(request.headers, "authorization")
    == Ok("Basic cGstbGYtMTpzay1sZi0y")
  assert list.key_find(request.headers, "x-langfuse-ingestion-version")
    == Ok("4")
}

pub fn request_keeps_a_path_prefix_test() {
  let assert Ok(request) =
    langfuse.request("https://example.com/langfuse/", "pk", "sk", json.null())
  assert request.path == "/langfuse/api/public/otel/v1/traces"
}

pub fn invalid_host_test() {
  let assert Error(_) = langfuse.request("not a url", "pk", "sk", json.null())
}
