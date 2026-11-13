import cloud/connection
import cloud/connections/sentry
import cloud/webhook
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/http
import gleam/string
import simplifile

fn fixture(name) {
  let assert Ok(body) =
    simplifile.read("test/fixtures/sentry/" <> name <> ".json")
  body
}

fn sign(body) {
  crypto.hmac(<<body:utf8>>, crypto.Sha256, <<"client-secret":utf8>>)
  |> bit_array.base16_encode
  |> string.lowercase
}

fn request(resource, body, signature) {
  webhook.Request(
    http.Post,
    "/",
    [
      #("sentry-hook-resource", resource),
      #("sentry-hook-signature", signature),
      #("request-id", "r1"),
    ],
    [],
    body,
  )
}

fn fields(event: connection.Event) {
  let assert v.Tagged(tag, v.Record(fields)) = event.value
  #(tag, fields)
}

fn text(fields, key) {
  let assert Ok(v.String(value)) = dict.get(fields, key)
  value
}

pub fn deliveries_must_be_signed_test() {
  let body = fixture("issue")
  let assert Error(webhook.Response(401, _)) =
    sentry.from_request(
      "sentry",
      "client-secret",
      request("issue", body, "bad"),
    )
  let assert Ok(event) =
    sentry.from_request(
      "sentry",
      "client-secret",
      request("issue", body, sign(body)),
    )
  assert event.id == "r1"
  assert event.live
}

pub fn issues_test() {
  let assert Ok(event) =
    sentry.from_webhook("sentry", "issue", "r1", fixture("issue"))
  let #(tag, fields) = fields(event)
  assert tag == "SentryIssue"
  assert text(fields, "action") == "created"
  assert text(fields, "short_id") == "APP-1Q"
  assert text(fields, "project") == "app"
  assert text(fields, "url")
    == "https://sentry.io/organizations/acme/issues/1170820242/"
}

pub fn event_alerts_test() {
  let assert Ok(event) =
    sentry.from_webhook("sentry", "event_alert", "r1", fixture("event_alert"))
  let #(tag, fields) = fields(event)
  assert tag == "SentryAlert"
  assert text(fields, "kind") == "event_alert"
  assert text(fields, "rule") == "Payments errors"
  assert text(fields, "title") == "Error: payment provider timed out"
}

pub fn metric_alerts_test() {
  let assert Ok(event) =
    sentry.from_webhook("sentry", "metric_alert", "r1", fixture("metric_alert"))
  let #(tag, fields) = fields(event)
  assert tag == "SentryAlert"
  assert text(fields, "action") == "critical"
  assert text(fields, "rule") == "Error rate above 5%"
  assert text(fields, "title") == "Critical: Error rate above 5%"
}

pub fn errors_test() {
  let assert Ok(event) =
    sentry.from_webhook("sentry", "error", "r1", fixture("error"))
  let #(tag, fields) = fields(event)
  assert tag == "SentryError"
  assert text(fields, "title") == "ReferenceError: user is not defined"
}

pub fn other_resources_test() {
  let assert Ok(event) =
    sentry.from_webhook(
      "sentry",
      "installation",
      "r1",
      "{\"action\":\"created\"}",
    )
  let #(tag, fields) = fields(event)
  assert tag == "SentryEvent"
  assert text(fields, "resource") == "installation"
}
