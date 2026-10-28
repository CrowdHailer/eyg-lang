//// AWS Signature Version 4 request signing.
////
//// https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv-create-signed-request.html

import gleam/bit_array
import gleam/dict
import gleam/http
import gleam/http/request.{type Request}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp.{type Timestamp}
import sha256

pub type Credentials {
  Credentials(
    access_key_id: String,
    secret_access_key: String,
    session_token: Option(String),
  )
}

/// Sign a request, adding the `x-amz-date`, `authorization` and, for temporary credentials,
/// `x-amz-security-token` headers.
pub fn sign(
  request: Request(BitArray),
  credentials: Credentials,
  region: String,
  service: String,
  time: Timestamp,
) -> Request(BitArray) {
  let #(date, datetime) = format_time(time)
  let request =
    request
    |> request.set_header("x-amz-date", datetime)
    |> fn(request) {
      case credentials.session_token {
        Some(token) ->
          request.set_header(request, "x-amz-security-token", token)
        None -> request
      }
    }

  let headers =
    [#("host", authority(request)), ..request.headers]
    |> list.map(fn(header) {
      #(string.lowercase(header.0), header_value(header.1))
    })
    |> list.filter(fn(header) {
      header.0 == "host"
      || header.0 == "content-type"
      || string.starts_with(header.0, "x-amz-")
    })
    |> list.fold(dict.new(), fn(headers, header) {
      let #(key, value) = header
      let value = case dict.get(headers, key) {
        Ok(previous) -> previous <> "," <> value
        Error(Nil) -> value
      }
      dict.insert(headers, key, value)
    })
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  let signed_headers = list.map(headers, fn(h) { h.0 }) |> string.join(";")
  let canonical_headers =
    list.map(headers, fn(h) { h.0 <> ":" <> h.1 <> "\n" }) |> string.concat

  let canonical_request =
    string.join(
      [
        http.method_to_string(request.method) |> string.uppercase,
        canonical_uri(request.path),
        canonical_query(request.query),
        canonical_headers,
        signed_headers,
        hex_sha256(request.body),
      ],
      "\n",
    )

  let scope = string.join([date, region, service, "aws4_request"], "/")
  let string_to_sign =
    string.join(
      [
        "AWS4-HMAC-SHA256",
        datetime,
        scope,
        hex_sha256(<<canonical_request:utf8>>),
      ],
      "\n",
    )

  let key =
    <<"AWS4":utf8, credentials.secret_access_key:utf8>>
    |> hmac(date)
    |> hmac(region)
    |> hmac(service)
    |> hmac("aws4_request")
  let signature = sha256.hmac(key, <<string_to_sign:utf8>>) |> hex

  request.set_header(
    request,
    "authorization",
    "AWS4-HMAC-SHA256 Credential="
      <> credentials.access_key_id
      <> "/"
      <> scope
      <> ", SignedHeaders="
      <> signed_headers
      <> ", Signature="
      <> signature,
  )
}

fn hmac(key, data: String) {
  sha256.hmac(key, <<data:utf8>>)
}

fn hex_sha256(bytes) {
  sha256.hash(bytes) |> hex
}

fn authority(request: Request(a)) {
  case request.port, request.scheme {
    None, _ | Some(443), http.Https | Some(80), http.Http -> request.host
    Some(port), _ -> request.host <> ":" <> int.to_string(port)
  }
}

fn header_value(value) {
  value
  |> string.replace("\t", " ")
  |> string.split(" ")
  |> list.filter(fn(part) { part != "" })
  |> string.join(" ")
}

fn hex(bytes) {
  bit_array.base16_encode(bytes) |> string.lowercase
}

/// `#("20150830", "20150830T123600Z")`
pub fn format_time(time: Timestamp) -> #(String, String) {
  let #(date, time) = timestamp.to_calendar(time, calendar.utc_offset)
  let date =
    int.to_string(date.year)
    <> pad(calendar.month_to_int(date.month))
    <> pad(date.day)
  #(
    date,
    date
      <> "T"
      <> pad(time.hours)
      <> pad(time.minutes)
      <> pad(time.seconds)
      <> "Z",
  )
}

fn pad(n) {
  string.pad_start(int.to_string(n), 2, "0")
}

/// Each path segment is encoded again, the path given is already encoded for the request.
fn canonical_uri(path) {
  case path {
    "" -> "/"
    _ ->
      string.split(path, "/")
      |> list.map(encode)
      |> string.join("/")
  }
}

fn canonical_query(query) {
  case query {
    None | Some("") -> ""
    Some(query) ->
      string.split(query, "&")
      |> list.map(fn(pair) {
        case string.split_once(pair, "=") {
          Ok(#(key, value)) -> #(key, value)
          Error(Nil) -> #(pair, "")
        }
      })
      |> list.sort(fn(a, b) {
        case string.compare(a.0, b.0) {
          order.Eq -> string.compare(a.1, b.1)
          order -> order
        }
      })
      |> list.map(fn(pair) { pair.0 <> "=" <> pair.1 })
      |> string.join("&")
  }
}

/// Percent encode everything but unreserved characters.
pub fn encode(segment: String) -> String {
  <<segment:utf8>>
  |> do_encode("")
}

fn do_encode(bytes, acc) {
  case bytes {
    <<byte, rest:bytes>> -> {
      let char = case is_unreserved(byte) {
        True -> {
          let assert Ok(char) = bit_array.to_string(<<byte>>)
          char
        }
        False -> "%" <> bit_array.base16_encode(<<byte>>)
      }
      do_encode(rest, acc <> char)
    }
    _ -> acc
  }
}

fn is_unreserved(byte) {
  { byte >= 0x41 && byte <= 0x5A }
  || { byte >= 0x61 && byte <= 0x7A }
  || { byte >= 0x30 && byte <= 0x39 }
  || byte == 0x2D
  || byte == 0x2E
  || byte == 0x5F
  || byte == 0x7E
}
