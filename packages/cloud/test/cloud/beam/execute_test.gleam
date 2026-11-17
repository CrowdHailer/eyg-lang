import cloud/beam/execute
import cloud/file_system
import cloud/helpers
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
