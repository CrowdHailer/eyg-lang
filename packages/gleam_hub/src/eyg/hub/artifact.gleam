//// Rules for the files of an artifact bundle.
////
//// Overlay checks them when an agent saves an artifact, and a hub checks them
//// again when a bundle is shared.

import eyg/hub/schema.{type ArtifactFile}
import gleam/bit_array
import gleam/list
import gleam/result
import gleam/set
import gleam/string

pub const max_files = 128

pub const max_bytes = 2_097_152

pub fn validate(
  name: String,
  files: List(ArtifactFile),
) -> Result(Nil, String) {
  use Nil <- result.try(
    case string.trim(name) == "" || string.length(name) > 120 {
      True -> Error("Artifact name must contain 1–120 characters")
      False -> Ok(Nil)
    },
  )
  let bytes =
    list.fold(files, 0, fn(total, file) {
      total + bit_array.byte_size(file.content)
    })
  use Nil <- result.try(
    case list.length(files) > max_files || bytes > max_bytes {
      True -> Error("A bundle may contain at most 128 files and 2 MiB")
      False -> Ok(Nil)
    },
  )
  use _ <- result.try(
    list.try_fold(files, set.new(), fn(seen, file) {
      case valid_path(file.path) && !set.contains(seen, file.path) {
        False -> Error("Invalid or duplicate bundle path: " <> file.path)
        True ->
          case valid_media_type(file.media_type) {
            False -> Error("Invalid media type: " <> file.media_type)
            True -> Ok(set.insert(seen, file.path))
          }
      }
    }),
  )
  case list.find(files, fn(file) { file.path == "index.html" }) {
    Ok(schema.ArtifactFile(media_type: "text/html", content:, ..)) ->
      bit_array.to_string(content)
      |> result.replace(Nil)
      |> result.replace_error("index.html must be UTF-8")
    _ -> Error("Bundle requires index.html with media_type text/html")
  }
}

/// A relative path without empty, `.` or `..` segments,
/// or characters that would change its meaning in a URL.
pub fn valid_path(path: String) -> Bool {
  !string.contains(path, "\\")
  && !string.contains(path, ":")
  && !string.contains(path, "?")
  && !string.contains(path, "#")
  && !string.contains(path, "%")
  && !string.contains(path, "\u{0000}")
  && !list.any(string.split(path, "/"), fn(segment) {
    segment == "" || segment == "." || segment == ".."
  })
}

/// A `type/subtype` media type without parameters,
/// safe to send as a header or write into a data URL.
pub fn valid_media_type(media_type: String) -> Bool {
  case string.split(media_type, "/") {
    [type_, subtype] -> token(type_) && token(subtype)
    _ -> False
  }
}

fn token(value) {
  value != ""
  && list.all(string.to_utf_codepoints(value), fn(codepoint) {
    let c = string.utf_codepoint_to_int(codepoint)
    { c >= 0x30 && c <= 0x39 }
    || { c >= 0x41 && c <= 0x5A }
    || { c >= 0x61 && c <= 0x7A }
    || string.contains("!#$&^_.+-", string.from_utf_codepoints([codepoint]))
  })
}

/// The id of a shared artifact is a lowercase UUID.
pub fn valid_id(id: String) -> Bool {
  string.length(id) == 36
  && list.index_map(string.to_graphemes(id), fn(char, index) {
    case index {
      8 | 13 | 18 | 23 -> char == "-"
      _ -> string.contains("0123456789abcdef", char)
    }
  })
  |> list.all(fn(valid) { valid })
}
