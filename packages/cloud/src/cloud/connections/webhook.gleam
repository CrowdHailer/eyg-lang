//// A webhook connection turns every HTTP request to its URL into an event.
////
//// `{name: "logs", source: Webhook({secret, split: True}), channel: "ops"}` accepts requests at
//// `/connections/logs/webhook` and any path under it. Each request is a `WebhookRequest` event,
//// given to the triggers of the connection's channel, so any service that can call a URL,
//// a log drain, an error tracker, a form or a deploy hook, can run triggers.
////
//// - `secret` optional. Requests must carry it, as a `sha256=` HMAC of the body in
////   `X-Hub-Signature-256` or `X-Signature-256`, as `Authorization: Bearer <secret>`,
////   or as a `token` query parameter for services that only let you set a URL.
////   Without a secret anyone who knows the URL can send events.
//// - `split` optional, default `False`. A JSON array body is one event per element,
////   so a log drain posting a batch of lines runs triggers for each line, every 404 for example.
//// - `respond` optional, a pure function from the request to `{status, body}`, the reply.
////   Without one requests are answered `200 accepted`. It sees the whole request before splitting.
////
//// Patterns are pure and cannot decode JSON, so the body is also given as `fields`,
//// a `{path, value}` pair for every string, number, boolean and null in it,
//// `status` for `{"status": 404}` and `lines.0.status` inside arrays.
//// Headers that carry credentials are not in events.

import cloud/connection
import cloud/data
import cloud/webhook
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/string

/// Whether a request carries the secret, any request is accepted without one.
pub fn authorised(
  secret: Result(String, Nil),
  request: webhook.Request,
) -> Bool {
  case secret {
    Error(Nil) -> True
    Ok(secret) -> {
      let signed = fn(header) {
        let signature = webhook.header(request, header)
        signature != ""
        && webhook.verify_sha256(secret, request.body, signature)
      }
      let equal = fn(given) {
        crypto.secure_compare(<<given:utf8>>, <<secret:utf8>>)
      }
      let bearer = webhook.header(request, "authorization")
      let token = webhook.query(request, "token")
      signed("x-hub-signature-256")
      || signed("x-signature-256")
      || string.starts_with(bearer, "Bearer ")
      && equal(string.drop_start(bearer, 7))
      || token != ""
      && equal(token)
    }
  }
}

/// The events of a request, one per element of a JSON array body when `split`.
pub fn events(
  connection: String,
  request: webhook.Request,
  split: Bool,
) -> List(connection.Event) {
  let parsed = json.parse(request.body, decode.dynamic)
  let bodies = case parsed, split {
    Ok(value), True ->
      case decode.run(value, decode.list(decode.dynamic)) {
        Ok(items) -> list.map(items, fn(item) { #(encode(item), Ok(item)) })
        Error(_) -> [#(request.body, Ok(value))]
      }
    Ok(value), False -> [#(request.body, Ok(value))]
    Error(_), _ -> [#(request.body, Error(Nil))]
  }
  let digest =
    crypto.hash(crypto.Sha256, <<request.body:utf8>>)
    |> bit_array.base16_encode
    |> string.slice(0, 16)
  list.index_map(bodies, fn(pair, index) {
    let #(body, parsed) = pair
    let fields = case parsed {
      Ok(value) -> flatten(value, "", [])
      Error(Nil) -> []
    }
    let value =
      data.tagged("WebhookRequest", to_value(connection, request, body, fields))
    connection.Event(
      connection:,
      id: digest <> "-" <> int.to_string(index),
      value:,
      summary: http.method_to_string(request.method) <> " " <> request.path,
      live: True,
    )
  })
}

/// The request as the record `WebhookRequest` events and `respond` receive.
pub fn to_value(
  connection: String,
  request: webhook.Request,
  body: String,
  fields: List(#(String, String)),
) {
  let pairs = fn(pairs, key, value) {
    data.list(
      list.map(pairs, fn(pair) {
        let #(k, v) = pair
        data.record([#(key, data.string(k)), #(value, data.string(v))])
      }),
    )
  }
  data.record([
    #("connection", data.string(connection)),
    #("method", data.string(http.method_to_string(request.method))),
    #("path", data.string(request.path)),
    #("query", pairs(list.filter(request.query, public_query), "key", "value")),
    #(
      "headers",
      pairs(list.filter(request.headers, public_header), "key", "value"),
    ),
    #("body", data.string(body)),
    #("fields", pairs(fields, "path", "value")),
  ])
}

/// The value of a request given to a connection's `respond` function.
pub fn request_value(connection: String, request: webhook.Request) {
  let fields = case json.parse(request.body, decode.dynamic) {
    Ok(value) -> flatten(value, "", [])
    Error(_) -> []
  }
  to_value(connection, request, request.body, fields)
}

fn public_query(pair: #(String, String)) {
  pair.0 != "token"
}

/// Headers that carry credentials are not given to programs.
fn public_header(pair: #(String, String)) {
  let name = string.lowercase(pair.0)
  !list.contains(["authorization", "cookie", "proxy-authorization"], name)
  && !list.any(["signature", "token", "secret", "key"], string.contains(name, _))
}

/// Every scalar in a JSON value as a `#(path, text)` pair, in document order.
pub fn flatten(
  value: Dynamic,
  prefix: String,
  acc: List(#(String, String)),
) -> List(#(String, String)) {
  list.reverse(do_flatten(value, prefix, list.reverse(acc)))
}

fn do_flatten(value, prefix, acc) {
  let join = fn(key) {
    case prefix {
      "" -> key
      _ -> prefix <> "." <> key
    }
  }
  case scalar(value) {
    Ok(text) -> [#(prefix, text), ..acc]
    Error(Nil) ->
      case decode.run(value, decode.list(decode.dynamic)) {
        Ok(items) ->
          list.index_fold(items, acc, fn(acc, item, index) {
            do_flatten(item, join(int.to_string(index)), acc)
          })
        Error(_) ->
          case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
            Ok(fields) ->
              fields
              |> dict.to_list
              |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
              |> list.fold(acc, fn(acc, pair) {
                do_flatten(pair.1, join(pair.0), acc)
              })
            Error(_) -> acc
          }
      }
  }
}

fn scalar(value) -> Result(String, Nil) {
  let decoder =
    decode.one_of(decode.string, [
      decode.int |> decode.map(int.to_string),
      decode.float |> decode.map(float.to_string),
      decode.bool
        |> decode.map(fn(b) {
          case b {
            True -> "true"
            False -> "false"
          }
        }),
    ])
  case decode.run(value, decoder), is_null(value) {
    Ok(text), _ -> Ok(text)
    Error(_), True -> Ok("null")
    Error(_), False -> Error(Nil)
  }
}

@external(erlang, "cloud_ffi", "is_null")
fn is_null(value: Dynamic) -> Bool

/// A JSON value back to its text, for one element of a split array.
fn encode(value: Dynamic) -> String {
  to_json(value) |> json.to_string
}

fn to_json(value: Dynamic) -> json.Json {
  case decode.run(value, decode.string) {
    Ok(s) -> json.string(s)
    Error(_) ->
      case decode.run(value, decode.int) {
        Ok(i) -> json.int(i)
        Error(_) ->
          case decode.run(value, decode.float) {
            Ok(f) -> json.float(f)
            Error(_) ->
              case decode.run(value, decode.bool) {
                Ok(b) -> json.bool(b)
                Error(_) ->
                  case decode.run(value, decode.list(decode.dynamic)) {
                    Ok(items) ->
                      json.preprocessed_array(list.map(items, to_json))
                    Error(_) ->
                      case
                        decode.run(
                          value,
                          decode.dict(decode.string, decode.dynamic),
                        )
                      {
                        Ok(fields) ->
                          fields
                          |> dict.to_list
                          |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
                          |> list.map(fn(pair) { #(pair.0, to_json(pair.1)) })
                          |> json.object
                        Error(_) -> json.null()
                      }
                  }
              }
          }
      }
  }
}
