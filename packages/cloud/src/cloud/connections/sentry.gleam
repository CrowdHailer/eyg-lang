//// Sentry sends issues, alerts and errors to a webhook, see `guides/cloud/connections/sentry.md`.
////
//// `{name: "sentry", source: Sentry({secret}), channel: "ops"}` accepts the webhooks of a Sentry
//// internal integration at `/connections/sentry/webhook`. Each delivery is signed with the
//// integration's client secret in `Sentry-Hook-Signature`, and its kind is `Sentry-Hook-Resource`.

import cloud/connection
import cloud/data
import cloud/webhook
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option
import gleam/result
import gleam/string

/// The hex HMAC-SHA256 of the body with the client secret, Sentry adds no `sha256=` prefix.
pub fn verify(secret: String, body: String, signature: String) -> Bool {
  let expected =
    crypto.hmac(<<body:utf8>>, crypto.Sha256, <<secret:utf8>>)
    |> bit_array.base16_encode
    |> string.lowercase
  crypto.secure_compare(<<expected:utf8>>, <<string.lowercase(signature):utf8>>)
}

/// Check a delivery's signature and convert it to an event.
pub fn from_request(
  connection: String,
  secret: String,
  request: webhook.Request,
) -> Result(connection.Event, webhook.Response) {
  let signature = webhook.header(request, "sentry-hook-signature")
  case verify(secret, request.body, signature) {
    False -> Error(webhook.Response(401, "invalid signature"))
    True -> {
      let resource = webhook.header(request, "sentry-hook-resource")
      let id = case webhook.header(request, "request-id") {
        "" -> {
          crypto.hash(crypto.Sha256, <<request.body:utf8>>)
          |> bit_array.base16_encode
          |> string.slice(0, 16)
        }
        id -> id
      }
      from_webhook(connection, resource, id, request.body)
      |> result.map_error(webhook.Response(400, _))
    }
  }
}

/// Convert a delivery, `resource` is the `Sentry-Hook-Resource` header.
pub fn from_webhook(
  connection: String,
  resource: String,
  id: String,
  body: String,
) -> Result(connection.Event, String) {
  let decoder = case resource {
    "issue" -> issue(connection)
    "event_alert" -> event_alert(connection)
    "metric_alert" -> metric_alert(connection)
    "error" -> error(connection)
    _ -> other(connection, resource)
  }
  use #(value, summary) <- result.map(
    json.parse(body, decoder)
    |> result.map_error(fn(reason) {
      "invalid " <> resource <> " delivery: " <> string.inspect(reason)
    }),
  )
  connection.Event(connection:, id:, value:, summary:, live: True)
}

fn issue(connection) {
  use action <- decode.field("action", decode.string)
  use #(id, short_id, title, culprit, level, status, project, url) <- decode.subfield(
    ["data", "issue"],
    {
      use id <- decode.field(
        "id",
        decode.one_of(decode.string, [decode.int |> decode.map(int.to_string)]),
      )
      use short_id <- optional_string("shortId")
      use title <- optional_string("title")
      use culprit <- optional_string("culprit")
      use level <- optional_string("level")
      use status <- optional_string("status")
      use project <- decode.optional_field(
        "project",
        "",
        decode.optional_field("slug", "", decode.string, decode.success),
      )
      use web_url <- optional_string("web_url")
      use permalink <- optional_string("permalink")
      let url = case web_url {
        "" -> permalink
        url -> url
      }
      decode.success(#(
        id,
        short_id,
        title,
        culprit,
        level,
        status,
        project,
        url,
      ))
    },
  )
  let value =
    data.tagged(
      "SentryIssue",
      data.record([
        #("connection", data.string(connection)),
        #("action", data.string(action)),
        #("id", data.string(id)),
        #("short_id", data.string(short_id)),
        #("title", data.string(title)),
        #("culprit", data.string(culprit)),
        #("level", data.string(level)),
        #("status", data.string(status)),
        #("project", data.string(project)),
        #("url", data.string(url)),
      ]),
    )
  decode.success(#(value, "issue " <> action <> ": " <> title))
}

fn alert(connection, kind, action, rule, title, level, url) {
  data.tagged(
    "SentryAlert",
    data.record([
      #("connection", data.string(connection)),
      #("kind", data.string(kind)),
      #("action", data.string(action)),
      #("rule", data.string(rule)),
      #("title", data.string(title)),
      #("level", data.string(level)),
      #("url", data.string(url)),
    ]),
  )
}

fn event_alert(connection) {
  use action <- decode.field("action", decode.string)
  use rule <- decode.subfield(["data", "triggered_rule"], decode.string)
  use #(title, level, url) <- decode.subfield(["data", "event"], {
    use title <- optional_string("title")
    use level <- optional_string("level")
    use web_url <- optional_string("web_url")
    use issue_url <- optional_string("issue_url")
    let url = case web_url {
      "" -> issue_url
      url -> url
    }
    decode.success(#(title, level, url))
  })
  let value = alert(connection, "event_alert", action, rule, title, level, url)
  decode.success(#(value, "alert " <> rule <> ": " <> title))
}

fn metric_alert(connection) {
  use action <- decode.field("action", decode.string)
  use #(rule, title, url) <- decode.field("data", {
    use title <- optional_string("description_title")
    use url <- optional_string("web_url")
    use rule <- decode.optional_field(
      "metric_alert",
      "",
      decode.optional_field(
        "alert_rule",
        "",
        decode.optional_field("name", "", decode.string, decode.success),
        decode.success,
      ),
    )
    decode.success(#(rule, title, url))
  })
  // A metric alert's action is its status, `critical`, `warning` or `resolved`.
  let value =
    alert(connection, "metric_alert", action, rule, title, action, url)
  decode.success(#(value, "metric alert " <> action <> ": " <> title))
}

fn error(connection) {
  use action <- decode.field("action", decode.string)
  use #(title, level, culprit, url, issue_url) <- decode.subfield(
    ["data", "error"],
    {
      use title <- optional_string("title")
      use level <- optional_string("level")
      use culprit <- optional_string("culprit")
      use url <- optional_string("web_url")
      use issue_url <- optional_string("issue_url")
      decode.success(#(title, level, culprit, url, issue_url))
    },
  )
  let value =
    data.tagged(
      "SentryError",
      data.record([
        #("connection", data.string(connection)),
        #("action", data.string(action)),
        #("title", data.string(title)),
        #("level", data.string(level)),
        #("culprit", data.string(culprit)),
        #("url", data.string(url)),
        #("issue_url", data.string(issue_url)),
      ]),
    )
  decode.success(#(value, "error: " <> title))
}

fn other(connection, resource) {
  use action <- decode.optional_field("action", "", decode.string)
  let value =
    data.tagged(
      "SentryEvent",
      data.record([
        #("connection", data.string(connection)),
        #("resource", data.string(resource)),
        #("action", data.string(action)),
      ]),
    )
  decode.success(#(value, resource <> " " <> action))
}

/// A string field that may be missing or null.
fn optional_string(field, then) {
  let decoder =
    decode.optional(decode.string) |> decode.map(option.unwrap(_, ""))
  decode.optional_field(field, "", decoder, then)
}
