import gleam/dynamic
import plinthx/browser/file

pub fn filenames_and_records_are_not_native_files_test() {
  assert Error(Nil) == file.from_dynamic(dynamic.string("hello.txt"))
  assert Error(Nil) == file.from_dynamic(dynamic.nil())
  let named =
    dynamic.properties([#(dynamic.string("name"), dynamic.string("hello.txt"))])
  assert Error(Nil) == file.from_dynamic(named)
}
