//// HTTP requests made by connections.

import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/result
import gleam/string

/// GET a URL and return the body of a successful response.
pub fn get(url: String) -> Result(String, String) {
  use request <- result.try(
    request.to(url) |> result.replace_error("invalid url " <> url),
  )
  let request =
    request
    |> request.set_header("user-agent", "eyg-cloud")
    |> request.set_header("accept", "application/json, application/xml, */*")
  use response <- result.try(
    httpc.configure()
    |> httpc.timeout(30_000)
    |> httpc.dispatch(request)
    |> result.map_error(fn(reason) { url <> ": " <> string.inspect(reason) }),
  )
  case response {
    response.Response(status: 200, body:, ..) -> Ok(body)
    response.Response(status:, ..) ->
      Error(url <> " returned " <> int.to_string(status))
  }
}
