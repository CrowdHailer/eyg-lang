// A package has a series of releases 
// Game studios have a franchise or title with many installments
// The organisation has permissions an a collection of series
// The series is self determined
// The name of the series is json
import eygir/encode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam_community/codec

// add to request
pub fn append_path(request, path) {
  request.set_path(request, request.path <> path)
}

pub fn set_body(request, mime, content) {
  request
  |> request.prepend_header("content-type", mime)
  |> request.set_body(content)
}

pub fn set_json(request, content) {
  set_body(request, "application/json", <<json.to_string(content):utf8>>)
}

const json_content = "application/json"

pub fn publish_request(base, series, next_release, source) {
  let payload = json.object([#("source", encode.encode(source))])
  base
  |> request.set_method(http.Post)
  |> append_path("/" <> series <> "/" <> int.to_string(next_release))
  |> set_json(payload)
}

// Could build from oas spec
pub fn publish_response(response) {
  let response.Response(status:, ..) = response
  case status {
    201 -> Ok(Nil)
    _ -> todo as "broknn protocol"
  }
}
