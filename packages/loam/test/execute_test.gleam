import birdie
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/dag_json
import gleam/dict
import gleam/list
import loam/execute
import loam/source
import multiformats/cid/v1

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
  state.Stack(state.Trace(value, state.Env([], dict.new())), meta, acc)
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
