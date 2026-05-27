import birdie
import eyg/cli/internal/execute
import eyg/cli/internal/source
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/dag_json
import gleam/dict
import gleam/list
import gleam/string
import multiformats/cid/v1
import simplifile
import touch_grass/file_system/append_file
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file

const origin = source.Disk("./test/fixtures/entry.eyg")

pub fn read_whole_file_test() {
  let input = read_file.Input(path: "hello.txt", offset: 0, limit: 1_000_000)
  let assert Ok(contents) = execute.read_file(origin, input)
  assert <<"Hello, World!">> == contents
}

pub fn read_empty_file_test() {
  let input = read_file.Input(path: "empty.txt", offset: 0, limit: 1_000_000)
  let assert Ok(contents) = execute.read_file(origin, input)
  assert <<>> == contents
}

pub fn read_subset_test() {
  let input = read_file.Input(path: "hello.txt", offset: 0, limit: 5)
  let assert Ok(contents) = execute.read_file(origin, input)
  assert <<"Hello">> == contents
}

pub fn read_offset_test() {
  let input = read_file.Input(path: "hello.txt", offset: 7, limit: 1_000_000)
  let assert Ok(contents) = execute.read_file(origin, input)
  assert <<"World!">> == contents
}

pub fn invalid_path_test() {
  let path = string.repeat("../", 100)
  let input = read_file.Input(path:, offset: 0, limit: 1_000_000)
  let assert Error(contents) = execute.read_file(origin, input)
  assert "invalid relative path outside filesystem" == contents
}

pub fn unknown_path_test() {
  let input = read_file.Input(path: "unknown.txt", offset: 0, limit: 1_000_000)
  let assert Error(contents) = execute.read_file(origin, input)
  assert "No such file or directory" == contents
}

pub fn read_directory_test() {
  let assert Ok(contents) = execute.read_directory(origin, path: "dir")
  assert [
      #("a.txt", read_directory.File(size: 1)),
      #("subdir", read_directory.Directory),
    ]
    == contents
}

pub fn write_file_test() {
  let _ = simplifile.delete_file("./test/fixtures/write.txt")
  let input = write_file.Input(path: "write.txt", contents: <<"test content">>)
  let assert Ok(Nil) = execute.write_file(origin, input)
  let read_input =
    read_file.Input(path: "write.txt", offset: 0, limit: 1_000_000)
  let assert Ok(contents) = execute.read_file(origin, read_input)
  assert <<"test content">> == contents
  let assert Ok(Nil) = simplifile.delete_file("./test/fixtures/write.txt")
}

pub fn write_file_invalid_path_test() {
  let path = string.repeat("../", 100)
  let input = write_file.Input(path:, contents: <<"data">>)
  let assert Error(_) = execute.write_file(origin, input)
}

pub fn append_file_test() {
  let _ = simplifile.delete_file("./test/fixtures/append.txt")
  let reset = write_file.Input(path: "append.txt", contents: <<"start">>)
  let assert Ok(Nil) = execute.write_file(origin, reset)
  let input = append_file.Input(path: "append.txt", contents: <<" end">>)
  let assert Ok(Nil) = execute.append_file(origin, input)
  let read_input =
    read_file.Input(path: "append.txt", offset: 0, limit: 1_000_000)
  let assert Ok(contents) = execute.read_file(origin, read_input)
  assert <<"start end">> == contents
  let assert Ok(Nil) = simplifile.delete_file("./test/fixtures/append.txt")
}

/// Run a snippet of EYG source text and capture the formatted runtime error.
fn snap_text(code: String) -> String {
  let assert Ok(node) = source.parse_input(code, source.Code(code))
  let assert Error(#(reason, location, _env, k)) = expression.execute(node, [])
  execute.render_error(reason, location, k, "")
}

pub fn undefined_variable_test() {
  snap_text("unknown")
  |> birdie.snap(title: "runtime: undefined variable")
}

pub fn undefined_variable_multiline_test() {
  snap_text("let x = 1\nlet y = 2\nunknown")
  |> birdie.snap(title: "runtime: undefined variable on third line")
}

pub fn undefined_builtin_test() {
  snap_text("!nonexistent_builtin")
  |> birdie.snap(title: "runtime: undefined builtin")
}

pub fn not_a_function_test() {
  snap_text("5(1)")
  |> birdie.snap(title: "runtime: not a function")
}

pub fn missing_field_test() {
  snap_text("{a: 1}.b")
  |> birdie.snap(title: "runtime: missing record field")
}

pub fn abort_test() {
  snap_text("perform Abort(\"oops\")")
  |> birdie.snap(title: "runtime: abort effect")
}

pub fn unhandled_effect_test() {
  snap_text("perform Custom(1)")
  |> birdie.snap(title: "runtime: unhandled custom effect")
}

pub fn multi_line_span_test() {
  // Without a trailing comma, the record's whole span survives the parser
  // and the renderer underlines every line the expression covers.
  snap_text("{a: 1\n}.b")
  |> birdie.snap(title: "runtime: multi-line span")
}

/// Build a continuation stack from an outermost-first list of Trace
/// frames. Each pair is `#(meta, arg)` — meta is the call-site
/// location, arg is the value passed in to that call.
fn stack_of(frames: List(#(source.Location, execute.Value))) -> execute.Stack {
  use acc, #(meta, value) <- list.fold(frames, state.Empty)
  state.Stack(state.Trace(value), meta, acc)
}

/// A user-code Disk origin stamped on a span of `code`.
fn at_disk(path: String, code: String, span: #(Int, Int)) -> source.Location {
  source.Location(source.Disk(path), source.Text(code, span))
}

/// A hub-fetched Content origin with no recoverable source.
fn at_content(cid: v1.Cid) -> source.Location {
  source.Location(source.Content(cid), source.Json)
}

/// A hub-fetched Release origin with no recoverable source.
fn at_release(package: String, version: Int, cid: v1.Cid) -> source.Location {
  source.Location(source.Release(package, version, cid), source.Json)
}

const main_eyg = "let lib = import \"./lib.eyg\"
lib(42)
"

pub fn abort_in_content_module_focuses_on_user_call_test() {
  // Failure inside a hub-fetched Content module: the renderer should
  // skip the no-source frames and focus on the call site in main.eyg
  // (the deepest user-code frame).
  let cid = dag_json.vacant_cid
  let reason = break.UnhandledEffect("Abort", v.String("bad arg"))
  // The failing meta is the abort expression inside the Content
  // module — no source available, but the renderer still names it.
  let failing = at_content(cid)
  let stack =
    stack_of([
      // outer: user code called the library entrypoint
      #(at_disk("main.eyg", main_eyg, #(29, 36)), v.Integer(42)),
      // inner: the library's outer helper called the library's inner
      // helper. Trace frame is inside the module so origin = Content.
      #(at_content(cid), v.Integer(42)),
    ])
  execute.render_error(reason, failing, stack, "")
  |> birdie.snap(
    title: "runtime: abort in hub Content module focuses user call",
  )
}

pub fn abort_in_release_module_focuses_on_user_call_test() {
  // Same shape as the Content test but using a Release origin so the
  // label renders as `@pkg:ver` instead of `#cid`.
  let cid = dag_json.vacant_cid
  let reason = break.UnhandledEffect("Abort", v.String("bad arg"))
  let failing = at_release("std", 3, cid)
  let stack =
    stack_of([
      #(at_disk("main.eyg", main_eyg, #(29, 36)), v.Integer(42)),
      #(at_release("std", 3, cid), v.Integer(42)),
    ])
  execute.render_error(reason, failing, stack, "")
  |> birdie.snap(
    title: "runtime: abort in hub Release module focuses user call",
  )
}

pub fn library_focus_skips_multiple_hub_frames_test() {
  // Several stacked hub frames - the focus should still land on the
  // single user-code frame at the top of the trace.
  let cid = dag_json.vacant_cid
  let reason = break.UnhandledEffect("Abort", v.String("bad arg"))
  let failing = at_content(cid)
  let stack =
    stack_of([
      #(at_disk("main.eyg", main_eyg, #(29, 36)), v.Integer(42)),
      #(at_release("std", 3, cid), v.Integer(42)),
      #(at_content(cid), v.Integer(42)),
      #(at_content(cid), v.Integer(42)),
    ])
  execute.render_error(reason, failing, stack, "")
  |> birdie.snap(title: "runtime: focus skips multiple hub frames")
}

const args_eyg = "let lib = import \"./lib.eyg\"
lib({name: \"alice\", age: 30})
"

pub fn arg_value_rendering_test() {
  // Each Trace frame carries the *evaluated* arg value, so the trace
  // shows the actual record/list/int that flowed in - not the source
  // expression that produced it.
  let cid = dag_json.vacant_cid
  let reason = break.UnhandledEffect("Abort", v.String("bad arg"))
  let failing = at_content(cid)
  let record =
    v.Record(
      dict.from_list([
        #("name", v.String("alice")),
        #("age", v.Integer(30)),
      ]),
    )
  let stack =
    stack_of([
      #(at_disk("main.eyg", args_eyg, #(29, 58)), record),
      #(at_content(cid), v.LinkedList([v.Integer(1), v.Integer(2)])),
    ])
  execute.render_error(reason, failing, stack, "")
  |> birdie.snap(title: "runtime: arg values render in stack trace")
}

pub fn release_with_unbound_cid_test() {
  // A release whose cid was not resolved at parse time still gets a
  // useful label (the renderer ignores the cid for Release).
  let reason = break.UnhandledEffect("Abort", v.String("bad arg"))
  let failing = at_release("missing_lib", 2, dag_json.vacant_cid)
  execute.render_error(reason, failing, state.Empty, "")
  |> birdie.snap(title: "runtime: release origin with unbound cid")
}
