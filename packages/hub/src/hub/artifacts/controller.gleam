//// Shared artifacts, bundles of files created in Overlay.
////
//// Files are served from the hub's own origin, so every file response is
//// sandboxed by its content security policy: documents get an opaque origin,
//// scripts run but nothing is fetched from outside the hub.

import eyg/hub/artifact as rules
import eyg/hub/schema
import gleam/bit_array
import gleam/bytes_tree
import gleam/crypto
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/uri
import hub/artifacts/data
import hub/server/context.{type Context}
import hub/web/utils
import pog
import wisp

/// Base64 content is a third larger than the files it encodes.
const max_upload = 3_000_000

/// Shares allowed from one address in ten minutes.
const max_shares = 30

pub fn share(
  request: Request(wisp.Connection),
  context: Context,
) -> Response(wisp.Body) {
  let request = wisp.set_max_body_size(request, max_upload)
  case utils.content_type(request) {
    Ok("application/json") -> {
      use body <- wisp.require_string_body(request)
      case json.parse(body, schema.share_artifact_decoder()) {
        Ok(#(name, files, previous)) ->
          case rules.validate(name, files) {
            Ok(Nil) -> {
              let ip = utils.client_ip(request)
              insert(name, files, previous, ip, context)
            }
            Error(reason) -> utils.api_reason(422, reason)
          }
        Error(_) -> utils.api_reason(400, "Expected an artifact name and files")
      }
    }
    _ -> wisp.unsupported_media_type(accept: ["application/json"])
  }
}

fn insert(name, files, previous, ip, context: Context) {
  use count <- utils.db_result(pog.execute(data.count_by_ip(ip), context.db))
  case count.rows {
    [count] if count >= max_shares ->
      utils.api_reason(429, "Too many artifacts shared, try again later")
    _ -> {
      use previous <- check_previous(previous, context)
      let secret =
        crypto.strong_random_bytes(32) |> bit_array.base64_url_encode(False)
      use returned <- utils.db_result(pog.execute(
        data.insert(name, files, ip, hash(secret)),
        context.db,
      ))
      case returned.rows {
        [id] -> {
          use _ <- link(previous, id, context)
          let shared = schema.SharedArtifact(id:, secret:)
          wisp.json_response(
            json.to_string(schema.shared_artifact_encode(shared)),
            201,
          )
          |> wisp.set_header("location", "/artifact/" <> id)
        }
        _ -> wisp.internal_server_error()
      }
    }
  }
}

/// A newer version needs the secret the previous version was shared with.
fn check_previous(previous, context: Context, then) {
  let forbidden =
    utils.api_reason(403, "The previous version is not shared with this secret")
  case previous {
    None -> then(None)
    Some(schema.SharedArtifact(id:, secret:)) ->
      case rules.valid_id(id) {
        False -> forbidden
        True -> {
          let query = data.shared_with(id, hash(secret))
          use returned <- utils.db_result(pog.execute(query, context.db))
          case returned.rows {
            [id] -> then(Some(id))
            _ -> forbidden
          }
        }
      }
  }
}

fn link(previous, id, context: Context, then) {
  case previous {
    None -> then(Nil)
    Some(previous) -> {
      use _ <- utils.db_result(pog.execute(data.link(previous, id), context.db))
      then(Nil)
    }
  }
}

fn hash(secret) {
  crypto.hash(crypto.Sha256, <<secret:utf8>>)
}

/// The bundle as JSON, so it can be opened and changed again.
pub fn get(id: String, context: Context) -> Response(wisp.Body) {
  use artifact <- find(id, context)
  use returned <- utils.db_result(pog.execute(data.files(id), context.db))
  wisp.json_response(
    json.to_string(schema.artifact_encode(artifact.name, returned.rows)),
    200,
  )
}

const file_policy =
  "sandbox allow-scripts; default-src 'none'; script-src 'self' 'unsafe-inline' data:; style-src 'self' 'unsafe-inline' data:; img-src 'self' data:; font-src 'self' data:; media-src 'self' data:; connect-src 'none'; frame-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'self'"

pub fn file(
  id: String,
  segments: List(String),
  context: Context,
) -> Response(wisp.Body) {
  let path =
    list.map(segments, fn(segment) {
      uri.percent_decode(segment) |> result.unwrap(segment)
    })
    |> string.join("/")
  case rules.valid_id(id) {
    False -> wisp.not_found()
    True ->
      case pog.execute(data.file(id, path), context.db) {
        Ok(pog.Returned(rows: [file], ..)) -> {
          // index.html is checked to be UTF-8 when shared.
          let content_type = case file.media_type {
            "text/html" -> "text/html; charset=utf-8"
            media_type -> media_type
          }
          wisp.response(200)
          |> wisp.set_header("content-type", content_type)
          |> wisp.set_header("content-security-policy", file_policy)
          |> wisp.set_header("x-content-type-options", "nosniff")
          // A sandboxed document has an opaque origin, fonts and module
          // scripts from its own bundle are cross origin requests.
          |> wisp.set_header("access-control-allow-origin", "*")
          |> wisp.set_header("referrer-policy", "no-referrer")
          |> wisp.set_header(
            "cache-control",
            "public, max-age=31536000, immutable",
          )
          |> wisp.set_body(wisp.Bytes(bytes_tree.from_bit_array(file.content)))
        }
        Ok(_) -> wisp.not_found()
        Error(_) -> wisp.response(503)
      }
  }
}

const page_policy =
  "default-src 'none'; style-src 'unsafe-inline'; frame-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

/// A page showing the artifact in a sandboxed frame.
pub fn page(id: String, context: Context) -> Response(wisp.Body) {
  use artifact <- find(id, context)
  let name = escape(artifact.name)
  let #(date, _time) = artifact.inserted_at
  let shared =
    int.to_string(date.day)
    <> " "
    <> calendar.month_to_string(date.month)
    <> " "
    <> int.to_string(date.year)
  // Like a Spring '83 board's <link rel="next">, an older version points to
  // the newer version shared after it.
  let #(next, newer) = case artifact.next {
    Some(next) -> #(
      "<link rel=\"next\" href=\"/artifact/" <> next <> "\">\n",
      " · <a href=\"/artifact/" <> next <> "\">newer version</a>",
    )
    None -> #("", "")
  }
  let html = "<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>" <> name <> " · Overlay</title>
" <> next <> "<style>
*{box-sizing:border-box}
html,body{height:100%;margin:0}
body{display:flex;flex-direction:column;background:#fff;color:#000;font-family:'Courier New',Courier,monospace}
header{display:flex;align-items:baseline;gap:1rem;padding:.6rem 1rem;border-bottom:1px solid #000}
header a{color:inherit;font-weight:bold;text-decoration:none}
header h1{flex:1;margin:0;font-size:1rem;font-weight:normal;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
header small{color:#555}
header small a{font-weight:normal;text-decoration:underline}
iframe{flex:1;width:100%;border:0}
</style>
</head>
<body>
<header><a href=\"/overlay/\">Overlay</a><h1>" <> name <> "</h1><small>Shared " <> shared <> newer <> "</small></header>
<iframe title=\"" <> name <> "\" src=\"/artifacts/" <> id <> "/files/index.html\" sandbox=\"allow-scripts\" referrerpolicy=\"no-referrer\" allow=\"camera 'none'; microphone 'none'; geolocation 'none'\"></iframe>
</body>
</html>
"
  wisp.html_response(html, 200)
  |> wisp.set_header("content-security-policy", page_policy)
  |> wisp.set_header("referrer-policy", "no-referrer")
}

fn find(id, context: Context, then) {
  case rules.valid_id(id) {
    False -> wisp.not_found()
    True ->
      case pog.execute(data.get(id), context.db) {
        Ok(pog.Returned(rows: [artifact], ..)) -> then(artifact)
        Ok(_) -> wisp.not_found()
        Error(_) -> wisp.response(503)
      }
  }
}

fn escape(text) {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
}
