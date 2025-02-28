import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/file
import plinth/browser/file_system

pub const l = "File.Read"

pub const lift = t.String

pub fn lower() {
  t.result(t.Binary, t.String)
}

pub fn blocking(name) {
  use name <- result.map(cast.as_string(name))
  promise.map(do(name), result_to_eyg)
}

pub fn handle(lift) {
  use p <- result.map(blocking(lift))
  v.Promise(p)
}

pub fn do(name) {
  use dir <- promise.try_await(file_system.show_directory_picker())
  use file <- promise.try_await(file_system.get_file_handle(dir, name, True))
  use file <- promise.try_await(file_system.get_file(file))
  use text <- promise.map(file.bytes(file))
  Ok(text)
}

pub fn result_to_eyg(result) {
  case result {
    Ok(data) -> v.ok(v.Binary(data))
    Error(reason) -> v.error(v.String(reason))
  }
}

pub fn task_to_eyg(task) {
  v.Promise({
    use result <- promise.map(task)
    result_to_eyg(result)
  })
}
