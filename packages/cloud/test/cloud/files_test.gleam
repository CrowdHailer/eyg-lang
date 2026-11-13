import cloud/beam/file_system
import cloud/files
import gleam/dict
import gleam/option.{None, Some}
import touch_grass/file_system/read_directory

fn start() {
  let assert Ok(fs) = files.seed(Some("test/fixtures/files"), dict.new())
  fs
}

pub fn seeded_files_are_readable_test() {
  let assert Ok(<<"---\nname: greet":utf8, _:bits>>) =
    file_system.read(start(), "/skills/greet/SKILL.md", 0, 1000)
}

pub fn write_append_and_normalize_test() {
  let assert #(Ok(_), fs) =
    file_system.write(start(), "/skills/../notes.txt", <<"hello":utf8>>)
  let assert #(Ok(_), fs) =
    file_system.append(fs, "/notes.txt", <<" world":utf8>>)
  assert file_system.read(fs, "notes.txt", 0, 100) == Ok(<<"hello world":utf8>>)
}

pub fn missing_parent_test() {
  let fs = start()
  let assert #(Error(_), _) = file_system.write(fs, "/a/b.txt", <<"x":utf8>>)
  let assert #(Ok(_), fs) = file_system.make_directory(fs, "/a")
  let assert #(Ok(_), _) = file_system.write(fs, "/a/b.txt", <<"x":utf8>>)
}

pub fn read_directory_test() {
  let assert #(Ok(_), fs) =
    file_system.write(start(), "/skills/note.md", <<"abc":utf8>>)
  assert file_system.read_directory(fs, "/skills")
    == Ok([
      #("greet", read_directory.Directory),
      #("note.md", read_directory.File(3)),
    ])
}

pub fn empty_start_test() {
  let assert Ok(fs) = files.seed(None, dict.new())
  assert file_system.read_directory(fs, "/") == Ok([])
}

pub fn slice_test() {
  assert files.slice(<<"hello":utf8>>, 1, 3) == <<"ell":utf8>>
  assert files.slice(<<"hello":utf8>>, 3, 100) == <<"lo":utf8>>
}
