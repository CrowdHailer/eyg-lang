import loam/sandbox
import loam/sandbox/fs
import loam/system
import simplifile

pub fn prompt_responses_are_sequential_and_independent_of_stdin_test() {
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_stdin("whole\nstream")
    |> sandbox.with_prompt_response(Ok("Ada"))
    |> sandbox.with_prompt_response(Ok(""))
    |> sandbox.with_prompt_response(Error(Nil))
  let workflow = {
    use first <- system.then(system.prompt("Name: "))
    use second <- system.then(system.prompt("Again: "))
    use failure <- system.then(system.prompt("Failure: "))
    use eof <- system.then(system.prompt("EOF: "))
    use stdin <- system.map(system.stdin())
    #(first, second, failure, eof, stdin)
  }
  let assert #(sandbox.Returned(responses), sandbox) =
    sandbox.run(workflow, sandbox)
  assert responses
    == #(Ok("Ada"), Ok(""), Error(Nil), Ok(""), Ok("whole\nstream"))
  assert sandbox.stdout == ["EOF: ", "Failure: ", "Again: ", "Name: "]
  assert sandbox.prompt_responses == []
  assert sandbox.stdin == []
}

pub fn file_system_effects_test() {
  let sandbox = sandbox.sandbox()
  let assert #(sandbox.Returned(created), sandbox) =
    system.create_directory("/data/nested") |> sandbox.run(sandbox)
  assert created == Ok(Nil)

  let assert #(sandbox.Returned(written), sandbox) =
    system.write_file("/data/nested/file", "contents") |> sandbox.run(sandbox)
  assert written == Ok(Nil)

  let assert #(sandbox.Returned(permissions), sandbox) =
    system.set_permissions("/data/nested/file", 0o000)
    |> sandbox.run(sandbox)
  assert permissions == Ok(Nil)

  let assert #(sandbox.Returned(contents), sandbox) =
    system.read_file("/data/nested/file") |> sandbox.run(sandbox)
  assert contents == Ok("contents")
  let assert #(sandbox.Returned(entries), sandbox) =
    system.read_directory("/data/nested") |> sandbox.run(sandbox)
  assert entries == Ok(["file"])

  let assert Ok(fs.File(permissions:, ..)) =
    fs.inspect(sandbox.file_system, "/data/nested/file")
  assert simplifile.file_permissions_to_octal(permissions) == 0o000
}

pub fn relative_filesystem_effects_use_sandbox_cwd_test() {
  let sandbox = sandbox.sandbox() |> sandbox.with_cwd("/project/src")
  let assert #(sandbox.Returned(created), sandbox) =
    system.create_directory("../data/nested") |> sandbox.run(sandbox)
  assert created == Ok(Nil)

  let assert #(sandbox.Returned(written), sandbox) =
    system.write_file("../data/nested/file", "contents") |> sandbox.run(sandbox)
  assert written == Ok(Nil)
  let assert #(sandbox.Returned(permissions), sandbox) =
    system.set_permissions("../data/./nested/file", 0o600)
    |> sandbox.run(sandbox)
  assert permissions == Ok(Nil)

  let assert #(sandbox.Returned(contents), sandbox) =
    system.read_file("../data/nested/file") |> sandbox.run(sandbox)
  assert contents == Ok("contents")
  let assert #(sandbox.Returned(entries), sandbox) =
    system.read_directory("../data/nested/") |> sandbox.run(sandbox)
  assert entries == Ok(["file"])
  let assert Ok(fs.File(permissions:, ..)) =
    fs.inspect(sandbox.file_system, "/project/data/nested/file")
  assert simplifile.file_permissions_to_octal(permissions) == 0o600
}
