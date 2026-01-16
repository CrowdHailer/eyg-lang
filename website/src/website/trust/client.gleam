import gleam/http
import gleam/http/request
import multiformats/base32
import spotless/origin

pub fn submit_request(endpoint, payload, signature) {
  let #(origin, path) = endpoint

  origin.to_request(origin)
  |> request.set_method(http.Post)
  |> request.set_path(path)
  |> request.set_header("content-type", "application/json")
  |> request.set_header(
    "authorization",
    "Signature " <> base32.encode(signature),
  )
  |> request.set_body(payload)
}
