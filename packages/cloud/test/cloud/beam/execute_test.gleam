import cloud/beam/execute
import cloud/file_system
import cloud/helpers
import cloud/server
import eyg/hub/cache
import eyg/ir/tree as ir
import gleam/dict
import gleam/erlang/process
import gleam/option.{Some}
import simplifile
import unixfs/mfs

fn start(code) {
  let state = helpers.state()
  let assert Ok(root) = execute.files(file_system.empty(), state)
  let assert Ok(policy) = simplifile.read("policy.eyg")
  let assert #(Ok(policy), state) = execute.load_policy(policy, state)
  execute.block(code, state, policy, root, fn(_) { Nil })
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

pub fn secrets_are_answered_by_the_caller_test() {
  let assert execute.Waiting(execute.Env("KEY"), state, root, resume) =
    start("perform Env(\"KEY\")")
  let assert execute.Finished(Ok(value), _, _, _) =
    resume(execute.Secret(Some("value")), state, root)
  assert "Some(\"value\")" == value
  let state = execute.State(..state, secrets: dict.from_list([#("KEY", "x")]))
  assert execute.Secret(Some("x")) == execute.perform(execute.Env("KEY"), state)
}

pub fn pin_packages_for_the_run_test() {
  let server = server.start(process.new_subject())
  let state =
    execute.State(
      ..helpers.state(),
      origin: server.origin(server),
      cache: server.release(cache.empty(), "lib", "1"),
    )
  let assert Ok(root) = execute.files(file_system.empty(), state)
  let assert Ok(policy) = simplifile.read("policy.eyg")
  let assert #(Ok(policy), state) = execute.load_policy(policy, state)
  let code = "let a = @lib\nlet _ = perform Random(1)\nlet b = @lib\n[a, b]"
  let assert execute.Waiting(_, state, root, resume) =
    execute.block(code, state, policy, root, fn(_) { Nil })
  // A new version is released while the code is waiting.
  let state =
    execute.State(..state, cache: server.release(state.cache, "lib", "2"))
  let assert execute.Finished(Ok("[1, 1]"), state, _, _) =
    resume(execute.Number(0), state, root)
  let assert Ok(_) = dict.get(state.pins, ir.Package("lib"))
}
