import eyg/analysis/type_/isomorphic as t
import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/clipboard
import plinth/browser/file

pub const l = "Download"

pub const lift = t.file

pub fn reply() {
  t.unit
}

pub fn type_() {
  #(l, #(lift, reply()))
}

pub fn blocking(lift) {
  use name <- result.try(cast.field("name", cast.as_string, lift))
  use content <- result.try(cast.field("content", cast.as_binary, lift))
  Ok(promise.resolve(result_to_eyg(do(name, content))))
}

pub fn non_blocking(lift) {
  use name <- result.try(cast.field("name", cast.as_string, lift))
  use content <- result.try(cast.field("content", cast.as_binary, lift))
  Ok(result_to_eyg(do(name, content)))
}

pub fn do(name, content) {
  let file = file.new(content, name)
  Ok(download_file(file))
}

pub fn result_to_eyg(result) {
  case result {
    Ok(Nil) -> v.ok(v.unit)
    Error(reason) -> v.error(v.Str(reason))
  }
}

@external(javascript, "../../../browser_ffi.mjs", "downloadFile")
fn download_file(file: file.File) -> Nil