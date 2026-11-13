import glasshouse/langfuse as export
import glasshouse/session
import glasshouse/store
import glasshouse_mock/langfuse
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}

fn sha256(bytes) {
  crypto.hash(crypto.Sha256, bytes)
}

fn basic(pair) {
  Ok("Basic " <> bit_array.base64_encode(<<pair:utf8>>, True))
}

pub fn langfuse_keys_are_accepted_test() {
  assert langfuse.authorized(basic("pk-lf-local:sk-lf-local"))
  assert !langfuse.authorized(basic("pk-lf-local"))
  assert !langfuse.authorized(basic("user:password"))
  assert !langfuse.authorized(Error(Nil))
}

/// A session with one prompt answered by one generation.
pub fn session() {
  let #(store, request) =
    store.put_binary(
      store.new(),
      <<
        "{\"model\":\"scripted\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}":utf8,
      >>,
      sha256,
    )
  let generation =
    session.Generation(
      id: "g1",
      started: 1_791_889_260_100,
      ended: 1_791_889_260_200,
      key: "key",
      request:,
      response: None,
      status: 200,
      thinking: "",
      content: "Hello there.",
      tool_calls: [],
      usage: session.Usage(input: 12, output: 3),
      source: session.Live,
      error: None,
    )
  let session =
    session.Session(
      id: "20261013T110100-abcd",
      started: 1_791_889_260_000,
      ended: 1_791_889_261_000,
      cwd: "/project",
      agent: Some(session.Agent(
        provider: "ollama",
        model: "scripted",
        system_prompt: "",
      )),
      events: [
        session.Prompt(at: 1_791_889_260_050, text: "hello"),
        session.Generated(generation:),
      ],
    )
  #(session, store)
}

fn payload() {
  let #(session, store) = session()
  <<json.to_string(export.payload(session, store, sha256)):utf8>>
}

pub fn glasshouse_payloads_become_traces_test() {
  let assert Ok(#(store, count)) = langfuse.ingest(langfuse.new(), payload())
  assert count > 1
  let assert [trace] = langfuse.traces(store)
  let #(session, _) = session()
  assert trace.id == export.trace_id(session, sha256)
  assert trace.name == "overlay session"
  assert trace.session == "20261013T110100-abcd"
  assert trace.input == "hello"
  assert trace.output == "Hello there."
  assert list.key_find(trace.metadata, "model") == Ok("scripted")
  let assert Ok(generation) =
    list.find(trace.observations, fn(o) { o.type_ == "generation" })
  assert generation.model == "scripted"
  assert generation.input_tokens == 12
  assert generation.output_tokens == 3
  assert langfuse.tokens(trace) == 15
}

pub fn uploading_twice_keeps_one_copy_test() {
  let assert Ok(#(once, _)) = langfuse.ingest(langfuse.new(), payload())
  let assert Ok(#(twice, _)) = langfuse.ingest(once, payload())
  assert dict.size(twice) == 1
  assert twice == once
}

pub fn other_bodies_are_rejected_test() {
  let assert Error(_) = langfuse.ingest(langfuse.new(), <<"{}">>)
  let assert Error(_) = langfuse.ingest(langfuse.new(), <<"not json">>)
}
