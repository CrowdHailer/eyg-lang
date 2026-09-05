import gleam/json
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
    Error(pog.ConstraintViolated(constraint:, ..)) -> {
      wisp.log_warning("violated constraint " <> constraint)
      api_reason(422, constraint)
    }
    Error(reason) -> {
      wisp.log_warning(string.inspect(reason))
      wisp.html_response(string.inspect(reason), 500)
    }
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
