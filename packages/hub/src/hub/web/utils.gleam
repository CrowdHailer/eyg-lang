import gleam/http/request.{type Request}
import gleam/json
import gleam/result
import gleam/string
import pog
import untethered/ledger/server
import wisp

pub fn do_decode(data, decoder, then) {
  case json.parse(data, decoder) {
    Ok(value) -> then(value)
    Error(reason) -> wisp.bad_request(string.inspect(reason))
  }
}

pub fn db_result(result, then) {
  case result {
    Ok(value) -> then(value)
    Error(pog.ConstraintViolated(detail:, ..)) -> api_reason(422, detail)
    Error(pog.PostgresqlError(message:, ..)) -> api_reason(422, message)
    Error(pog.UnexpectedArgumentCount(..)) ->
      api_reason(500, "db error " <> "UnexpectedArgumentCount")
    Error(pog.UnexpectedArgumentType(..)) ->
      api_reason(500, "db error " <> "UnexpectedArgumentType")
    Error(pog.UnexpectedResultType(_)) ->
      api_reason(500, "db error " <> "UnexpectedResultType")
    Error(pog.QueryTimeout) -> api_reason(503, "QueryTimeout")
    Error(pog.ConnectionUnavailable) -> api_reason(503, "ConnectionUnavailable")
  }
}

pub fn try_untethered(result, then) {
  case result {
    Ok(value) -> then(value)
    Error(reason) ->
      api_reason(
        server.denied_status_code(reason),
        server.denied_reason(reason),
      )
  }
}

pub fn api_reason(status, reason) {
  wisp.json_response(
    json.to_string(json.object([#("reason", json.string(reason))])),
    status,
  )
}

pub fn content_type(request: Request(wisp.Connection)) -> Result(String, Nil) {
  use value <- result.map(request.get_header(request, "content-type"))
  case string.split(value, ";") {
    [media_type, ..] -> media_type |> string.trim |> string.lowercase
    [] -> value
  }
}
