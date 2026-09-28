import gleam/http/request
import gleam/json
import gleam/option.{type Option, None, Some}

pub fn maybe(request, value: Option(t), func: fn(_, t) -> _) {
  case value {
    Some(value) -> func(request, value)
    None -> request
  }
}

pub fn set_bearer_token(request, token) {
  request
  |> request.set_header("authorization", "Bearer " <> token)
}

pub fn set_json(request, data) {
  request
  |> request.set_header("content-type", "application/json")
  |> request.set_body(<<json.to_string(data):utf8>>)
}
