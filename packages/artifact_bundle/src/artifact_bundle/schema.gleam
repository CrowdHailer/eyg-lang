import gleam/bit_array
import gleam/dynamic/decode
import gleam/json

/// A file of an artifact bundle.
pub type ArtifactFile {
  ArtifactFile(path: String, media_type: String, content: BitArray)
}

pub fn artifact_encode(name: String, files: List(ArtifactFile)) {
  json.object([#("name", json.string(name)), #("files", files_encode(files))])
}

pub fn artifact_decoder() -> decode.Decoder(#(String, List(ArtifactFile))) {
  use name <- decode.field("name", decode.string)
  use files <- decode.field("files", decode.list(file_decoder()))
  decode.success(#(name, files))
}

fn files_encode(files) {
  json.array(files, fn(file) {
    let ArtifactFile(path:, media_type:, content:) = file
    json.object([
      #("path", json.string(path)),
      #("media_type", json.string(media_type)),
      #("content", json.string(bit_array.base64_encode(content, True))),
    ])
  })
}

fn file_decoder() {
  use path <- decode.field("path", decode.string)
  use media_type <- decode.field("media_type", decode.string)
  use content <- decode.field("content", base64_decoder())
  decode.success(ArtifactFile(path:, media_type:, content:))
}

fn base64_decoder() {
  use encoded <- decode.then(decode.string)
  case bit_array.base64_decode(encoded) {
    Ok(content) -> decode.success(content)
    Error(Nil) -> decode.failure(<<>>, "base64")
  }
}
