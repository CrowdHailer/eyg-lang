//// HTTP requests delivered to a connection at `/connections/<name>/webhook`,
//// or a path under it, `/connections/<name>/webhook/<path>`.
////
//// Listening chat adapters, such as WhatsApp, receive requests here.

import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/list
import gleam/result
import gleam/string

pub type Request {
  Request(
    method: http.Method,
    /// The path after the connection's webhook URL, `/` for the URL itself.
    path: String,
    /// Header names are lowercase.
    headers: List(#(String, String)),
    query: List(#(String, String)),
    body: String,
  )
}

pub type Response {
  Response(status: Int, body: String)
}

/// Answers the webhook requests of one connection.
pub type Listener =
  fn(Request) -> Response

pub fn header(request: Request, name: String) -> String {
  list.key_find(request.headers, name) |> result.unwrap("")
}

pub fn query(request: Request, name: String) -> String {
  list.key_find(request.query, name) |> result.unwrap("")
}

pub fn accepted() -> Response {
  Response(200, "accepted")
}

/// Check a `sha256=<hex>` HMAC signature of the body, as sent by GitHub and Meta.
pub fn verify_sha256(secret: String, body: String, signature: String) -> Bool {
  let expected =
    crypto.hmac(<<body:utf8>>, crypto.Sha256, <<secret:utf8>>)
    |> bit_array.base16_encode
    |> string.lowercase
  crypto.secure_compare(<<{ "sha256=" <> expected }:utf8>>, <<signature:utf8>>)
}
