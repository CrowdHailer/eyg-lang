import cloud/slack/api/pagination
import cloud/slack/api/schema
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri
import oas/generator/utils

pub type Failure {
  SlackError(schema.ApiError)
  RateLimited(retry_after_seconds: Option(Int))
  UnexpectedStatus(response.Response(BitArray))
}

/// https://docs.slack.dev/reference/methods/auth.test/
pub fn auth_test_request(
  base: request.Request(BitArray),
) -> request.Request(BitArray) {
  base
  |> utils.set_method(http.Post)
  |> utils.append_path("/auth.test")
  |> utils.set_body("application/json; charset=utf-8", <<"{}":utf8>>)
}

pub fn auth_test_response(
  response: response.Response(BitArray),
) -> Result(Result(schema.Identity, Failure), json.DecodeError) {
  decode_response(response, schema.identity_decoder())
}

/// https://docs.slack.dev/reference/methods/conversations.list/
/// Note the channels field on the returned object is infact a list of conversations.
/// Discover public channels and private channels accessible to the bot.
pub fn conversations_list_request(
  base: request.Request(BitArray),
  cursor cursor: Option(String),
) -> request.Request(BitArray) {
  message_request(base, "/conversations.list", [
    #("types", Some("public_channel,private_channel")),
    #("exclude_archived", Some("false")),
    #("limit", Some("200")),
    #("cursor", cursor),
  ])
}

pub fn conversations_list_response(
  response: response.Response(BitArray),
) -> Result(
  Result(pagination.Page(List(schema.Channel)), Failure),
  json.DecodeError,
) {
  decode_response(response, pagination.decoder(schema.channels_decoder()))
}

pub fn conversations_history_request(
  base: request.Request(BitArray),
  channel: String,
  oldest oldest: Option(String),
  latest latest: Option(String),
  cursor cursor: Option(String),
  limit limit: Option(Int),
  inclusive inclusive: Option(Bool),
) -> request.Request(BitArray) {
  message_request(base, "/conversations.history", [
    #("channel", Some(channel)),
    #("oldest", oldest),
    #("latest", latest),
    #("cursor", cursor),
    #("limit", option.map(limit, int.to_string)),
    #(
      "inclusive",
      option.map(inclusive, fn(value) { json.to_string(json.bool(value)) }),
    ),
  ])
}

pub fn conversations_replies_request(
  base: request.Request(BitArray),
  channel: String,
  ts: String,
  oldest oldest: Option(String),
  latest latest: Option(String),
  cursor cursor: Option(String),
  limit limit: Option(Int),
) -> request.Request(BitArray) {
  message_request(base, "/conversations.replies", [
    #("channel", Some(channel)),
    #("ts", Some(ts)),
    #("oldest", oldest),
    #("latest", latest),
    #("cursor", cursor),
    #("limit", option.map(limit, int.to_string)),
    #("inclusive", Some("false")),
  ])
}

fn message_request(
  base: request.Request(BitArray),
  path: String,
  query: List(#(String, Option(String))),
) -> request.Request(BitArray) {
  let query =
    query
    |> list.filter_map(fn(pair) {
      case pair.1 {
        Some(value) -> Ok(#(pair.0, value))
        None -> Error(Nil)
      }
    })
  let req =
    base
    |> utils.set_method(http.Get)
    |> utils.append_path(path)
  // gleam_http 4's set_query leaves '+' unescaped. Use the query encoder so
  // opaque Slack cursors round-trip without '+' being interpreted as a space.
  request.Request(..req, query: Some(uri.query_to_string(query)))
}

pub fn conversations_history_response(
  response: response.Response(BitArray),
) -> Result(Result(pagination.Page(schema.History), Failure), json.DecodeError) {
  decode_response(response, pagination.decoder(schema.history_decoder()))
}

pub fn conversations_replies_response(
  response: response.Response(BitArray),
) -> Result(Result(pagination.Page(schema.History), Failure), json.DecodeError) {
  decode_response(response, pagination.decoder(schema.history_decoder()))
}

fn decode_response(
  response: response.Response(BitArray),
  decoder: decode.Decoder(a),
) -> Result(Result(a, Failure), json.DecodeError) {
  case response.status {
    200 -> {
      // Slack also reports API failures inside HTTP 200 responses.
      let envelope = {
        use ok <- decode.field("ok", decode.bool)
        case ok {
          True -> decode.map(decoder, Ok)
          False ->
            schema.api_error_decoder()
            |> decode.map(fn(error) { Error(SlackError(error)) })
        }
      }
      json.parse_bits(response.body, envelope)
    }
    429 -> {
      let seconds =
        response.get_header(response, "retry-after")
        |> result.try(int.parse)
        |> option.from_result
      Ok(Error(RateLimited(seconds)))
    }
    _ -> Ok(Error(UnexpectedStatus(response)))
  }
}
