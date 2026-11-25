import cloud/beam/execute
import cloud/config
import cloud/file_system
import cloud/server
import eyg/hub/cache
import eyg/interpreter/evaluation
import eyg/interpreter/expression
import eyg/ir/tree as ir
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import ogre/origin
import simplifile
import touch_grass/source
import unixfs/mfs

fn state() {
  let assert Ok(bucket) = config.bucket()
  execute.State(
    origin: origin.https("eyg.test"),
    cache: cache.ready(),
    secrets: dict.new(),
    bucket:,
    pins: dict.new(),
  )
}

// Code is checked with the effects the policy offers, before it runs.
pub fn an_empty_policy_offers_no_effects_test() {
  let state = state()
  let assert Ok(root) = execute.files(file_system.empty(), state)
  let assert execute.Finished(Error(reason), _, _, []) =
    execute.run("perform Random(10)", state, dict.new(), root, fn(_) { Nil })
  assert "missing row 'Random'" == reason
}

fn start(code) {
  let state = state()
  let assert Ok(root) = execute.files(file_system.empty(), state)
  execute.run(code, state, permissive(state), root, fn(_) { Nil })
}

const write =
  "perform WriteFile({path: \"/a.txt\", contents: !string_to_binary(\"a\")})"

pub fn wait_for_answer_test() {
  let assert execute.Waiting(execute.Random(10), state, root, resume) =
    start("let _ = " <> write <> "\nperform Random(10)")
  // File changes made before waiting are in the root.
  assert Ok(Ok(<<"a">>))
    == execute.files(file_system.read(root, "/a.txt"), state)
  let assert execute.Finished(Ok("7"), _, after, _) =
    resume(execute.Number(7), state, root)
  assert root == after
}

pub fn resume_with_another_root_test() {
  let assert execute.Waiting(execute.Now, state, _, resume) =
    start(
      "let _ = perform Now({})\nperform ReadFile({path: \"/b.txt\", offset: 0, limit: 10})",
    )
  let assert Ok(Ok(other)) =
    {
      use root <- mfs.then(file_system.empty())
      file_system.write(root, "/b.txt", <<"b">>)
    }
    |> execute.files(state)
  let assert execute.Finished(Ok(value), _, root, _) =
    resume(execute.Number(0), state, other)
  assert other == root
  assert "Ok(Binary(1 bytes): Yg==)" == value
}

pub fn complete_performs_effects_test() {
  let assert #(Ok("{}"), _, _, _) =
    start(
      "let _ = perform Random(10)\nlet _ = perform Flip({})\nperform Sleep(1)",
    )
    |> execute.complete
}

pub fn a_pure_evaluation_names_the_effect_it_refuses_test() {
  let assert Ok(source) = source.parse("perform Random(10)", source.Inline)
  let assert #(Error(reason), _) =
    evaluation.await(expression.execute(source, []))
    |> evaluation.map(result.map_error(_, execute.describe_debug))
    |> execute.pure(state())
  assert "unhandled effect Random({})" == reason
}

pub fn checking_pins_the_packages_code_refers_to_test() {
  let server = server.start(process.new_subject())
  let state =
    execute.State(
      ..state(),
      origin: server.origin(server),
      cache: server.release(cache.empty(), "lib", "1"),
    )
  let assert Ok(root) = execute.files(file_system.empty(), state)
  let assert execute.Finished(Ok("[1, 1]"), state, _, _) =
    execute.run("[@lib, @lib]", state, dict.new(), root, fn(_) { Nil })
  let assert Ok(_) = dict.get(state.pins, ir.Package("lib"))
}

pub fn a_package_that_was_not_pinned_is_refused_test() {
  let state =
    execute.State(..state(), cache: server.release(cache.empty(), "lib", "1"))
  let assert #(Error(reason), _) =
    execute.lookup_value(ir.Package("lib"), state)
  assert string.ends_with(reason, "not pinned")
}

fn files(files: List(#(String, String)), state) {
  let assert Ok(root) = execute.files(file_system.empty(), state)
  let assert Ok(Ok(root)) =
    execute.files(file_system.make_directory(root, "/lib"), state)
  list.fold(files, root, fn(root, file) {
    let #(path, contents) = file
    let assert Ok(Ok(root)) =
      execute.files(file_system.write(root, path, <<contents:utf8>>), state)
    root
  })
}

// A module's imports are relative to its own directory.
pub fn import_a_module_test() {
  let state = state()
  let root =
    files([#("/lib/a.eyg", "import \"./b.eyg\""), #("/lib/b.eyg", "2")], state)
  let code = "import \"./lib/a.eyg\""
  let assert execute.Finished(Ok("2"), _, _, _) =
    execute.run(code, state, dict.new(), root, fn(_) { Nil })
}

// Modules are checked as pure when the code that imports them is checked.
pub fn modules_are_pure_test() {
  let state = state()
  let root = files([#("/a.eyg", "perform Random(10)")], state)
  let policy = permissive(state)
  let assert execute.Finished(Error(reason), _, _, _) =
    execute.run("import \"./a.eyg\"", state, policy, root, fn(_) { Nil })
  assert "import ./a.eyg: missing row 'Random'" == reason
}

// Imports are loaded before the code runs, a module the code writes is not there yet.
pub fn imports_are_loaded_before_running_test() {
  let state = state()
  let assert Ok(root) = execute.files(file_system.empty(), state)
  let assert execute.Finished(Error(reason), _, _, _) =
    execute.run("import \"./missing.eyg\"", state, dict.new(), root, fn(_) {
      Nil
    })
  assert string.starts_with(reason, "import ./missing.eyg: ")
}

fn permissive(state) {
  let assert Ok(policy) = simplifile.read("policy.eyg")
  let assert #(Ok(policy), _) =
    execute.load_policy(
      policy,
      source.Host("policy.eyg"),
      state,
      execute.template(),
    )
  policy
}

pub fn secrets_are_answered_by_the_caller_test() {
  let assert execute.Waiting(execute.Env("KEY"), state, root, resume) =
    start("perform Env(\"KEY\")")
  let assert execute.Finished(Ok(value), _, _, _) =
    resume(execute.Secret(Some("value")), state, root)
  assert "Some(\"value\")" == value
  let state = execute.State(..state, secrets: dict.from_list([#("KEY", "x")]))
  assert execute.Secret(Some("x")) == execute.perform(execute.Env("KEY"), state)
}

// A program from the structural editor is checked like code, an unfinished program does not run.
pub fn a_program_is_checked_test() {
  let state = state()
  let assert Ok(root) = execute.files(file_system.empty(), state)
  let program = #(
    ir.Let("x", #(ir.Integer(1), Nil), #(ir.Variable("x"), Nil)),
    Nil,
  )
  let assert execute.Finished(Ok("1"), _, _, _) =
    execute.program(program, state, dict.new(), root, fn(_) { Nil })
  let unfinished = #(ir.Let("x", #(ir.Integer(1), Nil), #(ir.Vacant, Nil)), Nil)
  let assert execute.Finished(Error("code incomplete"), _, _, _) =
    execute.program(unfinished, state, dict.new(), root, fn(_) { Nil })
}
