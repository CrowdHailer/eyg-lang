import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result.{try}
import plinth/browser/file
import touch_grass/download

pub fn run(input) {
  let download.Input(name, content) = input
  promise.resolve(result_to_eyg(do(name, content)))
}

pub fn blocking(lift) {
  use input <- try(download.decode(lift))
  Ok(run(input))
}

pub fn non_blocking(lift) {
  use download.Input(name:, content:) <- try(download.decode(lift))

  Ok(result_to_eyg(do(name, content)))
}

pub fn do(name, content) {
  let file = file.new(content, name)
  Ok(download_file(file))
}

pub fn result_to_eyg(result) {
  case result {
    Ok(Nil) -> v.ok(v.unit())
    Error(reason) -> v.error(v.String(reason))
  }
}

@external(javascript, "../../../website_ffi.mjs", "downloadFile")
fn download_file(file: file.File) -> Nil
