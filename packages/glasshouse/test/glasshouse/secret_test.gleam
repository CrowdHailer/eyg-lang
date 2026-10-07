import eyg/interpreter/expression
import eyg/interpreter/table
import eyg/interpreter/value as v
import eyg/ir/dag_json as ir_json
import eyg/ir/tree as ir
import glasshouse/helpers.{sha256}
import glasshouse/journal
import glasshouse/lock
import glasshouse/recorder
import glasshouse/secret.{Secret}
import glasshouse/value
import gleam/bit_array
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string

const token = Secret("github", "ghp_s3cr3t")

pub fn closure_literals_and_captured_secrets_are_redacted_and_restored_test() {
  let body =
    ir.record([
      #("literal", ir.string("Bearer ghp_s3cr3t")),
      #("binary", ir.binary(<<"ghp_s3cr3t">>)),
      #("captured", ir.variable("saved")),
      #("unchanged", ir.integer(42)),
    ])
  let closure = v.Closure("_", body, [#("saved", v.String("ghp_s3cr3t"))])
  let redacted = secret.redact(closure, [token])
  let encoded = value.encode(redacted)
  assert !string.contains(ir_json.to_string(encoded), token.value)
  let assert Ok(result) = expression.call(redacted, [#(v.unit(), Nil)])
  assert result
    == v.Record(
      dict.from_list([
        #("literal", v.String("Bearer ⟦secret:github⟧")),
        #("binary", v.Binary(<<"⟦secret:github⟧":utf8>>)),
        #("captured", v.String("⟦secret:github⟧")),
        #("unchanged", v.Integer(42)),
      ]),
    )
  assert secret.restore(redacted, [token]) == closure
}

pub fn unused_captured_graphs_are_not_traversed_test() {
  let shared = shared(35, v.String(token.value))
  let redacted = secret.redact(shared, [token])
  let assert Ok(result) = expression.call(redacted, [#(v.unit(), Nil)])
  assert result == v.Integer(42)
  assert !string.contains(
    ir_json.to_string(value.encode(redacted)),
    token.value,
  )
}

fn shared(depth, value) {
  case depth {
    0 -> value
    _ ->
      shared(
        depth - 1,
        v.Closure("_", ir.integer(42), [
          #("left", value),
          #("right", value),
        ]),
      )
  }
}

pub fn redact_replaces_in_nested_values_test() {
  let request =
    v.Record(
      dict.from_list([
        #("headers", v.LinkedList([v.String("Bearer ghp_s3cr3t")])),
        #("body", v.Binary(<<"token=ghp_s3cr3t">>)),
      ]),
    )
  let redacted = secret.redact(request, [token])
  let expected =
    v.Record(
      dict.from_list([
        #("headers", v.LinkedList([v.String("Bearer ⟦secret:github⟧")])),
        #("body", v.Binary(<<"token=⟦secret:github⟧":utf8>>)),
      ]),
    )
  assert redacted == expected
  assert secret.restore(redacted, [token]) == request
}

pub fn non_utf8_binaries_are_unchanged_test() {
  let bytes = v.Binary(<<255, 0, 255>>)
  assert secret.redact(bytes, [token]) == bytes
}

pub fn longer_secrets_are_replaced_first_test() {
  let short = Secret("short", "abc")
  let long = Secret("long", "abcdef")
  assert secret.redact(v.String("abcdef abc"), [short, long])
    == v.String("⟦secret:long⟧ ⟦secret:short⟧")
}

pub fn empty_secrets_are_ignored_test() {
  assert secret.redact(v.String("text"), [Secret("empty", "")])
    == v.String("text")
}

pub fn dummy_replays_redact_to_the_same_placeholder_test() {
  let real = secret.redact(v.String("Bearer ghp_s3cr3t"), [token])
  let dummy = secret.dummy("github")
  let replayed = secret.redact(v.String("Bearer " <> dummy.value), [dummy])
  assert real == replayed
}

pub fn reveals_test() {
  assert secret.reveals("x ghp_s3cr3t y", [token])
  assert !secret.reveals("nothing here", [token])
}

pub fn credential_variables_test() {
  assert secret.is_credential_variable("GITHUB_TOKEN")
  assert secret.is_credential_variable("openai_api_key")
  assert secret.is_credential_variable("DB_PASSWORD")
  assert !secret.is_credential_variable("HOME")
  assert !secret.is_credential_variable("PATH")
}

pub fn locks_keep_a_hash_of_each_secret_test() {
  let recorder =
    recorder.new(sha256)
    |> recorder.add_secret(secret.Secret("github", "ghp_real_token"))
  let lock = recorder.lock_secrets(recorder, lock.empty())
  assert dict.get(lock.secrets, "github")
    == Ok(recorder.digest(sha256, "ghp_real_token"))
  // The value itself is never in the lock.
  let encoded = json.to_string(lock.encode(lock))
  assert !string.contains(encoded, "ghp_real_token")
  assert json.parse(encoded, lock.decoder()) == Ok(lock)
}

pub fn locks_without_secrets_still_decode_test() {
  let assert Ok(lock) =
    json.parse(
      "{\"files\": {}, \"packages\": {}, \"versions\": []}",
      lock.decoder(),
    )
  assert lock == lock.empty()
}

pub fn credential_json_discovery_keeps_unrelated_fields_test() {
  let bytes = <<
    "{\"OPENAI_API_KEY\":null,\"tokens\":{\"access_token\":\"fixture-access-123\",\"refresh_token\":\"fixture-refresh-123\",\"id_token\":\"fixture-id-123\",\"account_id\":\"account\"},\"public\":\"keep\"}",
  >>
  let secrets = secret.in_json(bytes, "file:/cache/auth.json")
  assert list.length(secrets) == 3
  assert secret.reveals(
    "fixture-access-123 fixture-refresh-123 fixture-id-123",
    secrets,
  )
  assert !secret.reveals("account keep", secrets)
  assert secret.in_json(<<255>>, "file") == []
  assert secret.in_json(<<"not JSON">>, "file") == []
}

pub fn file_and_rotated_oauth_credentials_are_redacted_before_capture_test() {
  let file = <<
    "{
    \"tokens\":{\"access_token\":\"fixture-old-access-123\",\"refresh_token\":\"fixture-old-refresh-123\",\"id_token\":\"fixture-old-id-123\"}
  }",
  >>
  let request =
    v.Record(
      dict.from_list([
        #("host", v.String("auth.example.com")),
        #("path", v.String("/oauth/token")),
      ]),
    )
  let reply =
    v.ok(
      v.Record(
        dict.from_list([
          #(
            "body",
            v.Binary(<<
              "{\"access_token\":\"fixture-new-access-123\",\"refresh_token\":\"fixture-new-refresh-123\"}",
            >>),
          ),
        ]),
      ),
    )
  let recorded =
    recorder.new(sha256)
    |> recorder.with_threshold(1)
    |> recorder.record(
      "ReadFile",
      v.unit(),
      v.ok(v.Binary(file)),
      journal.Performed,
      Some("/cache/auth.json"),
      0,
      1,
    )
    |> recorder.record(
      "Fetch",
      request,
      reply,
      journal.Performed,
      Some("/oauth/token"),
      1,
      1,
    )
  let entries = recorder.journal(recorded)
  let encoded =
    list.map(entries, journal.encode)
    |> json.array(fn(value) { value })
    |> json.to_string
  assert !string.contains(encoded, "fixture-old-access-123")
  assert !string.contains(encoded, "fixture-old-refresh-123")
  assert !string.contains(encoded, "fixture-old-id-123")
  assert !string.contains(encoded, "fixture-new-access-123")
  assert !string.contains(encoded, "fixture-new-refresh-123")
  assert list.length(recorder.secrets(recorded)) == 5
  let assert [read, fetched] = entries
  let assert Ok(v.Tagged("Ok", v.Binary(bytes))) =
    value.decode(read.reply, recorder.store(recorded), Nil)
  let assert Ok(text) = bit_array.to_string(bytes)
  assert !secret.reveals(text, recorder.secrets(recorded))
  assert string.contains(
    text,
    "⟦secret:json:file:/cache/auth.json:tokens:access_token⟧",
  )
  let assert Ok(v.Tagged("Ok", v.Record(fields))) =
    value.decode(fetched.reply, recorder.store(recorded), Nil)
  let assert Ok(v.Binary(bytes)) = dict.get(fields, "body")
  let assert Ok(text) = bit_array.to_string(bytes)
  assert !secret.reveals(text, recorder.secrets(recorded))
  assert string.contains(
    text,
    "⟦secret:json:http:auth.example.com/oauth/token:access_token⟧",
  )
  let #(result, _) =
    recorder.encode(recorded, v.String("Bearer fixture-new-access-123"))
  assert result
    == value.encode(v.String(
      "Bearer ⟦secret:json:http:auth.example.com/oauth/token:access_token⟧",
    ))
}

pub fn secrets_in_query_facts_are_redacted_and_restored_test() {
  let original =
    v.Table(
      table.from_list([
        #("Token", [v.String(token.value)]),
      ]),
      [],
    )
  let redacted = secret.redact(original, [token])
  assert !string.contains(
    ir_json.to_string(value.encode(redacted)),
    token.value,
  )
  assert secret.restore(redacted, [token]) == original
}
