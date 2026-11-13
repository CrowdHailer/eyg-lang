import cloud/connection
import cloud/connections/webhook as webhooks
import cloud/webhook
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/http
import gleam/list
import gleam/string

fn request(headers, query, body) {
  webhook.Request(http.Post, "/errors", headers, query, body)
}

fn sign(body) {
  let hex =
    crypto.hmac(<<body:utf8>>, crypto.Sha256, <<"s3cret":utf8>>)
    |> bit_array.base16_encode
    |> string.lowercase
  "sha256=" <> hex
}

pub fn requests_without_a_secret_are_accepted_test() {
  assert webhooks.authorised(Error(Nil), request([], [], "{}"))
}

pub fn requests_carry_the_secret_test() {
  let secret = Ok("s3cret")
  let body = "{\"status\":404}"
  assert webhooks.authorised(
    secret,
    request([#("x-hub-signature-256", sign(body))], [], body),
  )
  assert webhooks.authorised(
    secret,
    request([#("x-signature-256", sign(body))], [], body),
  )
  assert webhooks.authorised(
    secret,
    request([#("authorization", "Bearer s3cret")], [], body),
  )
  assert webhooks.authorised(secret, request([], [#("token", "s3cret")], body))
  assert !webhooks.authorised(secret, request([], [], body))
  assert !webhooks.authorised(
    secret,
    request([#("authorization", "Bearer wrong")], [#("token", "")], body),
  )
  assert !webhooks.authorised(
    secret,
    request([#("x-signature-256", sign("other"))], [], body),
  )
}

fn record(event: connection.Event) {
  let assert v.Tagged("WebhookRequest", v.Record(fields)) = event.value
  fields
}

fn pairs(fields, key) {
  let assert Ok(v.LinkedList(items)) = dict.get(fields, key)
  list.map(items, fn(item) {
    let assert v.Record(pair) = item
    let values = dict.values(pair)
    let assert [v.String(a), v.String(b)] = case dict.to_list(pair) {
      [#("key", k), #("value", value)] -> [k, value]
      [#("path", p), #("value", value)] -> [p, value]
      _ -> values
    }
    #(a, b)
  })
}

pub fn json_bodies_are_flattened_into_fields_test() {
  let body =
    "{\"status\":404,\"path\":\"/missing\",\"ok\":false,\"user\":null,\"tags\":[\"a\",{\"b\":1.5}]}"
  let assert [event] = webhooks.events("logs", request([], [], body), False)
  let fields = record(event)
  assert pairs(fields, "fields")
    == [
      #("ok", "false"),
      #("path", "/missing"),
      #("status", "404"),
      #("tags.0", "a"),
      #("tags.1.b", "1.5"),
      #("user", "null"),
    ]
  assert dict.get(fields, "body") == Ok(v.String(body))
  assert dict.get(fields, "path") == Ok(v.String("/errors"))
  assert event.summary == "POST /errors"
}

pub fn arrays_are_split_when_asked_test() {
  let body = "[{\"status\":200},{\"status\":404}]"
  let assert [first, second] =
    webhooks.events("logs", request([], [], body), True)
  assert pairs(record(first), "fields") == [#("status", "200")]
  assert pairs(record(second), "fields") == [#("status", "404")]
  assert dict.get(record(second), "body") == Ok(v.String("{\"status\":404}"))
  assert first.id != second.id
  let assert [whole] = webhooks.events("logs", request([], [], body), False)
  assert list.length(pairs(record(whole), "fields")) == 2
}

pub fn other_bodies_are_text_test() {
  let assert [event] =
    webhooks.events("logs", request([], [], "GET /missing 404"), True)
  assert pairs(record(event), "fields") == []
  assert dict.get(record(event), "body") == Ok(v.String("GET /missing 404"))
}

pub fn credentials_are_not_in_events_test() {
  let headers = [
    #("authorization", "Bearer s3cret"),
    #("x-signature-256", "sha256=00"),
    #("x-api-key", "k"),
    #("content-type", "application/json"),
  ]
  let query = [#("token", "s3cret"), #("source", "vercel")]
  let assert [event] =
    webhooks.events("logs", request(headers, query, "{}"), False)
  assert pairs(record(event), "headers")
    == [#("content-type", "application/json")]
  assert pairs(record(event), "query") == [#("source", "vercel")]
}
