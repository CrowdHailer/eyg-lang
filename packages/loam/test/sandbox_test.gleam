import loam/sandbox
import loam/sandbox/fs
import loam/system
import simplifile

pub fn file_system_effects_test() {
  let sandbox = sandbox.sandbox()
  let #(created, sandbox) =
    system.create_directory("/data/nested") |> sandbox.run(sandbox)
  assert created == Ok(Nil)

  let #(written, sandbox) =
    system.write_file("/data/nested/file", "contents") |> sandbox.run(sandbox)
  assert written == Ok(Nil)

  let #(permissions, sandbox) =
    system.set_permissions("/data/nested/file", 0o000)
    |> sandbox.run(sandbox)
  assert permissions == Ok(Nil)

  let #(contents, sandbox) =
    system.read_file("/data/nested/file") |> sandbox.run(sandbox)
  assert contents == Ok("contents")
  let #(entries, sandbox) =
    system.read_directory("/data/nested") |> sandbox.run(sandbox)
  assert entries == Ok(["file"])

  let assert Ok(fs.File(permissions:, ..)) =
    fs.inspect(sandbox.file_system, "/data/nested/file")
  assert simplifile.file_permissions_to_octal(permissions) == 0o000
}
