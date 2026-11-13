//// Build a journal as a program runs.
////
//// The runtime calls `record` after each effect has been answered.
//// Values are encoded canonically, secrets are redacted and large binaries move to the store.

import eyg/interpreter/value as v
import eyg/ir/dag_json as ir_json
import eyg/ir/tree as ir
import glasshouse/journal.{type Answer, type Entry, Entry}
import glasshouse/lock.{type Lock}
import glasshouse/secret.{type Secret, Secret}
import glasshouse/store.{type Sha256, type Store}
import glasshouse/value
import gleam/bit_array
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/string
import multiformats/cid/v1

/// The label of the effect that mounts secrets, its replies are always redacted.
pub const mount_secret = "MountSecret"

/// Binaries larger than this many bytes are stored as modules rather than inline.
pub const default_threshold = 512

pub opaque type Recorder {
  Recorder(
    entries: List(Entry),
    store: Store,
    secrets: List(Secret),
    threshold: Int,
    sha256: Sha256,
  )
}

pub fn new(sha256: Sha256) -> Recorder {
  Recorder(
    entries: [],
    store: store.new(),
    secrets: [],
    threshold: default_threshold,
    sha256:,
  )
}

/// Continue recording into an existing store, i.e. one shared by every run in a session.
pub fn with_store(recorder: Recorder, store: Store) -> Recorder {
  Recorder(..recorder, store:)
}

pub fn with_threshold(recorder: Recorder, threshold: Int) -> Recorder {
  Recorder(..recorder, threshold:)
}

/// Secrets already known, i.e. mounted by an earlier run in the same session.
pub fn with_secrets(recorder: Recorder, secrets: List(Secret)) -> Recorder {
  Recorder(..recorder, secrets:)
}

/// Add a secret value that must never be recorded.
pub fn add_secret(recorder: Recorder, secret: Secret) -> Recorder {
  Recorder(..recorder, secrets: [secret, ..recorder.secrets])
}

/// Record an effect that has been answered.
pub fn record(
  recorder: Recorder,
  label: String,
  lift: v.Value(m, c),
  reply: v.Value(m, c),
  answer: Answer,
  path: Option(String),
  started: Int,
  duration: Int,
) -> Recorder {
  let recorder = case label, lift, reply {
    "MountSecret", v.String(name), v.Tagged("Ok", v.String(secret)) ->
      add_secret(recorder, Secret(name:, value: secret))
    "Env", v.String(name), v.Tagged("Some", v.String(secret)) ->
      case secret.is_credential_variable(name) {
        True -> add_secret(recorder, Secret(secret.variable_name(name), secret))
        False -> recorder
      }
    "ReadFile", _, v.Tagged("Ok", v.Binary(bytes)) ->
      secret.in_json(bytes, "file:" <> option.unwrap(path, "unknown"))
      |> list.fold(recorder, add_secret)
    "Fetch", v.Record(request), v.Tagged("Ok", v.Record(response)) ->
      case
        dict.get(response, "body"),
        dict.get(request, "host"),
        dict.get(request, "path")
      {
        Ok(v.Binary(bytes)), Ok(v.String(host)), Ok(v.String(path)) ->
          secret.in_json(bytes, "http:" <> host <> path)
          |> list.fold(recorder, add_secret)
        _, _, _ -> recorder
      }
    _, _, _ -> recorder
  }
  let #(lift, recorder) = capture(recorder, lift)
  let #(reply, recorder) = capture(recorder, reply)
  let entry = Entry(label:, lift:, reply:, answer:, path:, started:, duration:)
  Recorder(..recorder, entries: [entry, ..recorder.entries])
}

/// Encode a value with secrets redacted and large binaries stored,
/// i.e. the final value of a run.
pub fn encode(
  recorder: Recorder,
  value: v.Value(m, c),
) -> #(value.Encoded, Recorder) {
  capture(recorder, value)
}

fn capture(recorder: Recorder, value: v.Value(m, c)) {
  let Recorder(store:, secrets:, threshold:, sha256:, ..) = recorder
  let encoded = value.encode(secret.redact(value, secrets))
  let #(encoded, store) = value.externalize(encoded, store, threshold, sha256)
  #(encoded, Recorder(..recorder, store:))
}

/// The CID of a value without storing it,
/// used to identify a request a policy changed without keeping its contents.
pub fn fingerprint(recorder: Recorder, value: v.Value(m, c)) -> String {
  value.fingerprint(value, recorder.sha256)
}

/// Add a binary to the store, i.e. a source file read to pin a program.
pub fn store_binary(
  recorder: Recorder,
  bytes: BitArray,
) -> #(Recorder, String) {
  let #(store, id) = store.put_binary(recorder.store, bytes, recorder.sha256)
  #(Recorder(..recorder, store:), id)
}

/// Add a module to the store.
pub fn store_node(recorder: Recorder, node: ir.Node(a)) -> #(Recorder, String) {
  let #(store, id) = store.put_node(recorder.store, node, recorder.sha256)
  #(Recorder(..recorder, store:), id)
}

/// The CID a module would be stored under, without storing it.
pub fn module_cid(recorder: Recorder, node: ir.Node(a)) -> String {
  ir_json.to_block(node)
  |> store.cid(recorder.sha256)
  |> v1.to_string
}

/// Does the text contain a registered secret.
pub fn reveals(recorder: Recorder, text: String) -> Bool {
  secret.reveals(text, recorder.secrets)
}

/// Redact registered secrets from text that is recorded outside the journal.
pub fn redact_text(recorder: Recorder, text: String) -> String {
  case secret.redact(v.String(text), recorder.secrets) {
    v.String(text) -> text
    _ -> text
  }
}

/// The entries recorded so far, oldest first.
pub fn journal(recorder: Recorder) -> List(Entry) {
  list.reverse(recorder.entries)
}

pub fn store(recorder: Recorder) -> Store {
  recorder.store
}

pub fn secrets(recorder: Recorder) -> List(Secret) {
  recorder.secrets
}

/// Add a hash of every secret known to the recorder to a lock, the values themselves are never recorded.
pub fn lock_secrets(recorder: Recorder, lock: Lock) -> Lock {
  list.fold(recorder.secrets, lock, fn(lock, secret) {
    lock.add_secret(lock, secret.name, digest(recorder.sha256, secret.value))
  })
}

/// The hex SHA-256 of a secret, as a lock records it.
pub fn digest(sha256: Sha256, value: String) -> String {
  sha256(<<value:utf8>>) |> bit_array.base16_encode |> string.lowercase
}

/// Start a new journal, keeping the store and secrets.
pub fn restart(recorder: Recorder) -> Recorder {
  Recorder(..recorder, entries: [])
}

pub fn sha256(recorder: Recorder) -> Sha256 {
  recorder.sha256
}
