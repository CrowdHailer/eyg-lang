import cloud/fs
import cloud/modules
import cloud/shell
import cloud/store
import eyg/interpreter/value as v
import gleam/string

fn setup(files) {
  let s = store.new()
  let root =
    list_fold(files, fs.empty(s), fn(root, file) {
      let #(path, code) = file
      let assert Ok(root) = fs.write_file(s, root, path, <<code:utf8>>)
      root
    })
  #(s, root)
}

fn list_fold(items, acc, f) {
  case items {
    [] -> acc
    [first, ..rest] -> list_fold(rest, f(acc, first), f)
  }
}

pub fn import_value_test() {
  let #(s, root) = setup([#("/lib.eyg", "!int_add(20, 22)")])
  assert modules.value(s, root, "lib.eyg") == Ok(v.Integer(42))
  assert modules.value(s, root, "/lib.eyg") == Ok(v.Integer(42))
}

pub fn nested_imports_are_relative_to_the_file_test() {
  let #(s, root) =
    setup([
      #("/lib/a.eyg", "let b = import \"./b.eyg\"\n!int_add(b, 1)"),
      #("/lib/b.eyg", "41"),
    ])
  assert modules.value(s, root, "lib/a.eyg") == Ok(v.Integer(42))
}

pub fn missing_file_test() {
  let #(s, root) = setup([])
  let assert Error(message) = modules.value(s, root, "nope.eyg")
  assert string.contains(message, "no such file")
}

pub fn import_cycle_test() {
  let #(s, root) =
    setup([#("/a.eyg", "import \"./b.eyg\""), #("/b.eyg", "import \"./a.eyg\"")])
  let assert Error(message) = modules.value(s, root, "a.eyg")
  assert string.contains(message, "type errors")
    || string.contains(message, "cycle")
}

pub fn modules_have_no_effects_test() {
  let #(s, root) = setup([#("/fx.eyg", "perform StandardOut(\"hi\")")])
  let assert Error(_) = modules.value(s, root, "fx.eyg")
}

pub fn shell_runs_imports_from_the_file_system_test() {
  let #(s, root) = setup([#("/lib.eyg", "{double: (x) -> { !int_add(x, x) }}")])
  let snapshot = shell.Snapshot(scope: [], root:)
  let assert Ok(source) =
    shell.parse("let lib = import \"lib.eyg\"\nlib.double(21)")
  let #(output, _) = shell.run(s, source, snapshot)
  assert output == [shell.Result("42")]
}

pub fn shell_reports_failed_import_test() {
  let #(s, root) = setup([])
  let snapshot = shell.Snapshot(scope: [], root:)
  let assert Ok(source) = shell.parse("import \"missing.eyg\"")
  let #(output, after) = shell.run(s, source, snapshot)
  let assert [shell.Stderr(message), shell.Failure(_), shell.Hint(_)] = output
  assert string.contains(message, "missing.eyg")
  assert after == snapshot
}

pub fn dag_json_modules_test() {
  let #(s, root) = setup([#("/n.json", "{\"0\":\"i\",\"v\":7}")])
  assert modules.value(s, root, "n.json") == Ok(v.Integer(7))
}
