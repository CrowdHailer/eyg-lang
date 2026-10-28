import eyg/interpreter/value as v
import gleam/dict
import overlay/web/workspace
import touch_grass/file_system/append_file
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file

fn write(workspace, path, text) {
  workspace.perform(
    workspace,
    workspace.WriteFile(write_file.Input(path:, contents: <<text:utf8>>)),
  )
}

fn read(workspace, path) {
  let #(_, value) =
    workspace.perform(
      workspace,
      workspace.ReadFile(read_file.Input(path:, offset: 0, limit: 1_000_000)),
    )
  value
}

fn entry(name, type_) {
  v.Record(dict.from_list([#("name", v.String(name)), #("type", type_)]))
}

fn file(size) {
  v.Tagged("File", v.Record(dict.from_list([#("size", v.Integer(size))])))
}

pub fn write_then_read_test() {
  let #(workspace, value) = write(workspace.new(), "notes.md", "hello")
  assert v.ok(v.unit()) == value
  assert v.ok(v.Binary(<<"hello">>)) == read(workspace, "notes.md")
  // A leading slash or dot is the workspace root.
  assert v.ok(v.Binary(<<"hello">>)) == read(workspace, "/notes.md")
  assert v.ok(v.Binary(<<"hello">>)) == read(workspace, "./notes.md")
  assert [#("notes.md", <<"hello">>)] == workspace.files(workspace)
}

pub fn read_a_slice_test() {
  let workspace = workspace.from_files([#("data.txt", <<"abcdef">>)])
  let slice = fn(offset, limit) {
    workspace.perform(
      workspace,
      workspace.ReadFile(read_file.Input(path: "data.txt", offset:, limit:)),
    ).1
  }
  assert v.ok(v.Binary(<<"cd">>)) == slice(2, 2)
  assert v.ok(v.Binary(<<"ef">>)) == slice(4, 100)
  assert v.ok(v.Binary(<<>>)) == slice(10, 2)
  assert v.error(v.String("offset and limit must not be negative"))
    == slice(-1, 2)
  assert v.error(v.String("no such file: missing.txt"))
    == read(workspace, "missing.txt")
}

pub fn files_need_an_existing_directory_test() {
  let #(workspace, value) = write(workspace.new(), "notes/today.md", "x")
  assert v.error(v.String("no such directory: notes")) == value
  assert [] == workspace.files(workspace)

  let #(workspace, value) =
    workspace.perform(workspace, workspace.MakeDirectory("notes/2026"))
  assert v.ok(v.unit()) == value
  let #(workspace, value) = write(workspace, "notes/today.md", "x")
  assert v.ok(v.unit()) == value
  let #(_, value) = write(workspace, "notes/2026", "x")
  assert v.error(v.String("a directory exists at: notes/2026")) == value
}

pub fn paths_cannot_leave_the_workspace_test() {
  let #(workspace, value) = write(workspace.new(), "../secret.txt", "x")
  assert v.error(v.String("path leaves the workspace: ../secret.txt")) == value
  let #(workspace, value) = write(workspace, "a/../b.txt", "x")
  assert v.ok(v.unit()) == value
  assert [#("b.txt", <<"x">>)] == workspace.files(workspace)
}

pub fn a_directory_cannot_be_created_under_a_file_test() {
  let original = workspace.from_files([#("notes", <<"a file">>)])
  let #(after, value) =
    workspace.perform(original, workspace.MakeDirectory("notes/today"))
  assert v.error(v.String("a file exists at: notes/today")) == value
  assert original == after
}

pub fn deleting_the_last_file_keeps_its_directory_test() {
  let original = workspace.from_files([#("notes/today.md", <<>>)])
  let #(after, _) =
    workspace.perform(original, workspace.DeleteFile("notes/today.md"))
  let #(_, value) = workspace.perform(after, workspace.ReadDirectory("notes"))
  assert v.ok(v.LinkedList([])) == value
}

pub fn append_creates_and_extends_test() {
  let append = fn(workspace, text) {
    workspace.perform(
      workspace,
      workspace.AppendFile(
        append_file.Input(path: "log.txt", contents: <<text:utf8>>),
      ),
    )
  }
  let #(workspace, value) = append(workspace.new(), "a")
  assert v.ok(v.unit()) == value
  let #(workspace, _) = append(workspace, "b")
  assert v.ok(v.Binary(<<"ab">>)) == read(workspace, "log.txt")
}

pub fn delete_a_file_test() {
  let workspace = workspace.from_files([#("a.txt", <<>>)])
  let #(workspace, value) =
    workspace.perform(workspace, workspace.DeleteFile("a.txt"))
  assert v.ok(v.unit()) == value
  assert [] == workspace.files(workspace)
  let #(_, value) = workspace.perform(workspace, workspace.DeleteFile("a.txt"))
  assert v.error(v.String("no such file: a.txt")) == value
}

pub fn list_a_directory_test() {
  let workspace =
    workspace.from_files([
      #("README.md", <<"readme">>),
      #("notes/one.md", <<"1">>),
      #("src/app/main.eyg", <<"5">>),
    ])
  let #(workspace, _) =
    workspace.perform(workspace, workspace.MakeDirectory("tmp"))
  let list = fn(path) {
    workspace.perform(workspace, workspace.ReadDirectory(path)).1
  }
  assert v.ok(
      v.LinkedList([
        entry("README.md", file(6)),
        entry("notes", v.Tagged("Directory", v.unit())),
        entry("src", v.Tagged("Directory", v.unit())),
        entry("tmp", v.Tagged("Directory", v.unit())),
      ]),
    )
    == list(".")
  assert v.ok(v.LinkedList([entry("app", v.Tagged("Directory", v.unit()))]))
    == list("src")
  assert v.ok(v.LinkedList([entry("main.eyg", file(1))])) == list("/src/app/")
  assert v.error(v.String("no such directory: docs")) == list("docs")
}
