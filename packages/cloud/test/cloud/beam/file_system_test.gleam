import cloud/beam/file_system
import gleam/dict
import touch_grass/file_system/read_directory

pub fn read_directory_test() {
  let fs = file_system.new(dict.new())
  let assert #(Ok(Nil), fs) = file_system.make_directory(fs, "/notes")
  let assert #(Ok(Nil), fs) = file_system.write(fs, "/notes/a.txt", <<"a">>)
  let assert #(Ok(Nil), fs) = file_system.write(fs, "/b.txt", <<"bb">>)
  assert Ok([
      #("b.txt", read_directory.File(2)),
      #("notes", read_directory.Directory),
    ])
    == file_system.read_directory(fs, "/")
}
