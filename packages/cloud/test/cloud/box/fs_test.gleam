import cloud/beam/execute
import cloud/box/fs
import cloud/file_system
import cloud/helpers
import gleam/list
import gleam/string
import unixfs/mfs

fn check(files: List(#(String, String))) {
  let state = helpers.state()
  let assert Ok(#(errors, _, _)) =
    {
      use root <- mfs.then(file_system.empty())
      use root <- mfs.then(write_all(files, root))
      let assert Ok(root) = root
      fs.check(root, state)
    }
    |> execute.files(state)
  errors
}

fn write_all(files, root) {
  case files {
    [] -> mfs.Done(Ok(root))
    [#(path, code), ..files] -> {
      use root <- mfs.then(file_system.make_directory(root, path <> "/.."))
      use root <- mfs.try(root)
      use root <- mfs.then(file_system.write(root, path, <<code:utf8>>))
      use root <- mfs.try(root)
      write_all(files, root)
    }
  }
}

pub fn modules_and_other_files_test() {
  assert []
    == check([
      #("/lib/double.eyg", "(x) -> { !int_add(x, x) }"),
      #("/notes/todo.txt", "let x ="),
    ])
}

pub fn effects_inside_functions_test() {
  assert [] == check([#("/log.eyg", "(x) -> { perform Log(x) }")])
}

pub fn syntax_error_test() {
  let assert [error] = check([#("/bad.eyg", "let x =")])
  assert string.starts_with(error, "/bad.eyg: ")
}

pub fn type_error_test() {
  let assert [error] = check([#("/bad.eyg", "!int_add(1, \"two\")")])
  assert string.starts_with(error, "/bad.eyg: ")
}

pub fn top_level_effect_test() {
  let assert [_] = check([#("/bad.eyg", "perform Log(\"hi\")")])
}

pub fn relative_and_absolute_imports_test() {
  assert []
    == check([
      #("/lib/one.eyg", "1"),
      #("/lib/two.eyg", "!int_add(import \"./one.eyg\", import \"one.eyg\")"),
      #(
        "/app/main.eyg",
        "!int_add(import \"../lib/two.eyg\", import \"/lib/one.eyg\")",
      ),
    ])
}

pub fn import_type_mismatch_test() {
  let assert [error] =
    check([
      #("/name.eyg", "\"Bob\""),
      #("/main.eyg", "!int_add(1, import \"./name.eyg\")"),
    ])
  assert string.starts_with(error, "/main.eyg: ")
}

pub fn missing_import_test() {
  let errors = check([#("/main.eyg", "import \"./gone.eyg\"")])
  assert 2 == list.length(errors)
}

pub fn missing_import_does_not_stop_checking_other_modules_test() {
  let errors =
    check([
      #("/main.eyg", "import \"./gone.eyg\""),
      #("/other.eyg", "!int_add(1, \"two\")"),
    ])
  assert 3 == list.length(errors)
  assert list.any(errors, string.starts_with(_, "/other.eyg: "))
}

pub fn import_cycle_test() {
  let errors =
    check([
      #("/a.eyg", "import \"./b.eyg\""),
      #("/b.eyg", "import \"./a.eyg\""),
    ])
  assert [] != errors
}
