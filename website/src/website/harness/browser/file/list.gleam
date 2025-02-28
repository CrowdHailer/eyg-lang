import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import gleam/result
import gleam/string
import plinth/browser/file_system

pub const l = "File.List"

pub const lift = t.unit

pub fn lower() {
  t.result(t.List(t.String), t.String)
}

pub fn type_() {
  #(l, #(lift, lower()))
}

pub fn blocking(lift) {
  use Nil <- result.map(cast.as_unit(lift, Nil))
  promise.map(do(), result_to_eyg)
}

pub fn handle(lift) {
  use p <- result.map(blocking(lift))
  v.Promise(p)
}

pub fn do() {
  use dir <- promise.try_await(file_system.show_directory_picker())
  use #(entries, _) <- promise.try_await(file_system.all_entries(dir))
  promise.resolve(Ok(list.map(array.to_list(entries), string.inspect)))
}

pub fn result_to_eyg(result) {
  case result {
    Ok(data) -> v.ok(v.LinkedList(list.map(data, v.String)))
    Error(reason) -> v.error(v.String(reason))
  }
}

pub fn task_to_eyg(task) {
  v.Promise({
    use result <- promise.map(task)
    result_to_eyg(result)
  })
}
