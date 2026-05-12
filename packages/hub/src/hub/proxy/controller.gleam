import gleam/bytes_tree
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/list
import gleam/option.{None}
import gleam/string
import wisp

pub fn to(service, path, request) {
  case service {
    "dnsimple" -> {
      use body <- wisp.require_bit_array_body(request)
      let request.Request(
        method:,
        headers:,
        body: _,
        scheme: _,
        host: _,
        port: _,
        path: _,
        query:,
      ) = request

      let scheme = http.Https
      let host = "api.dnsimple.com"
      let port = None
      let headers = take_keys(headers, ["content-type", "authorization"])
      let path = string.join(["", ..path], "/")

      let request =
        request.Request(
          method:,
          headers:,
          body:,
          scheme:,
          host:,
          port:,
          path:,
          query:,
        )

      case httpc.send_bits(request) {
        Ok(response.Response(status:, headers:, body:)) -> {
          let headers = take_keys(headers, ["content-type"])
          let body = wisp.Bytes(bytes_tree.from_bit_array(body))
          response.Response(status:, headers:, body:)
        }
        Error(_) -> wisp.internal_server_error()
      }
    }
    _ -> wisp.not_found()
  }
}

/// The request headers. The keys must always be lowercase.
fn take_keys(fields, keys) {
  list.filter(fields, fn(field) {
    let #(key, _) = field
    list.contains(keys, key)
  })
}
