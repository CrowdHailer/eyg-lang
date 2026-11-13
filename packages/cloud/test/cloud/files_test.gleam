import cloud/files
import gleam/erlang/process
import gleam/option.{None, Some}
import touch_grass/file_system/read_directory

fn start() {
  let assert Ok(fs) = files.start(Some("test/fixtures/files"))
  fs
}

fn write(fs, path, text) {
  files.call(fs, files.Update(files.Write(<<text:utf8>>), path, "tester", _))
}

pub fn seeded_files_are_readable_test() {
  let fs = start()
  let assert Ok(<<"---\nname: greet":utf8, _:bits>>) =
    files.call(fs, files.Read("/skills/greet/SKILL.md", _))
}

pub fn write_and_read_test() {
  let fs = start()
  let assert Ok(Nil) = write(fs, "/notes.txt", "hello")
  assert files.call(fs, files.Read("/notes.txt", _)) == Ok(<<"hello":utf8>>)
  let assert Ok(Nil) =
    files.call(fs, files.Update(
      files.Append(<<" world":utf8>>),
      "/notes.txt",
      "tester",
      _,
    ))
  assert files.call(fs, files.Read("notes.txt", _))
    == Ok(<<"hello world":utf8>>)
}

pub fn missing_parent_test() {
  let fs = start()
  let assert Error("/a/b.txt: No such file or directory") =
    write(fs, "/a/b.txt", "x")
  let assert Ok(Nil) =
    files.call(fs, files.Update(files.MakeDirectory, "/a", "tester", _))
  let assert Ok(Nil) = write(fs, "/a/b.txt", "x")
}

pub fn read_directory_test() {
  let fs = start()
  let assert Ok(Nil) = write(fs, "/skills/note.md", "abc")
  let assert Ok(entries) = files.call(fs, files.ReadDirectory("/skills", _))
  assert entries
    == [
      #("greet", read_directory.Directory),
      #("note.md", read_directory.File(3)),
    ]
}

pub fn delete_test() {
  let fs = start()
  let assert Ok(Nil) =
    files.call(fs, files.Update(files.Delete, "/skills/greet", "tester", _))
  let assert Error(_) = files.call(fs, files.Read("/skills/greet/SKILL.md", _))
}

pub fn changes_are_reported_test() {
  let fs = start()
  let changes = process.new_subject()
  process.send(fs, files.Subscribe(changes))
  let assert Ok(Nil) = write(fs, "/skills/../notes.txt", "hello")
  assert process.receive(changes, 100)
    == Ok(files.Change("/notes.txt", "tester"))
}

pub fn empty_start_test() {
  let assert Ok(fs) = files.start(None)
  assert files.call(fs, files.ReadDirectory("/", _)) == Ok([])
}

pub fn slice_test() {
  assert files.slice(<<"hello":utf8>>, 1, 3) == <<"ell":utf8>>
  assert files.slice(<<"hello":utf8>>, 3, 100) == <<"lo":utf8>>
}
