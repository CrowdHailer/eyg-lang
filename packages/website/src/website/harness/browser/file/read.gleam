import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/javascript/promise
import gleam/result
import plinth/browser/file
import plinth/browser/file_system
import touch_grass/read

pub const l = "ReadFile"

pub const lift = t.String

pub fn lower() {
  t.result(t.Binary, t.String)
}

pub fn blocking(name) {
  use name <- result.map(read.decode(name))
  promise.map(do(name), read.encode)
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

pub fn task_to_eyg(task) {
  v.Promise({
    use result <- promise.map(task)
    read.encode(result)
  })
}
