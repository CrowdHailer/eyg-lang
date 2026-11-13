import glasshouse/bundle
import glasshouse/sha256
import glasshouse/store
import gleam/dict
import loam/environment
import loam/sandbox
import loam/sandbox/fs
import loam/system
import loam/virtual

fn environment() {
  let fixture =
    sandbox.sandbox()
    |> sandbox.with_directory("/workspace/empty")
    |> sandbox.with_files([#("/workspace/a", "same"), #("/workspace/b", "same")])
  environment.Environment(
    ..environment.new(),
    files: fixture.file_system,
    variables: dict.from_list([#("REGION", "test")]),
  )
}

pub fn portable_environment_keeps_content_empty_directories_and_identity_test() {
  let prepared = environment.seal(environment(), sha256.hash)
  let assert Ok(transported) =
    bundle.from_string(bundle.to_string(prepared), sha256.hash)
  let assert Ok(restored) = environment.open(transported)
  assert restored.files == environment().files
  assert restored.variables == environment().variables
  assert environment.seal(restored, sha256.hash).root == prepared.root
  // Equal file bytes are one shared binary block, including across directories.
  let #(blocks, file) = store.put_binary(store.new(), <<"same">>, sha256.hash)
  assert store.get(prepared.store, file) == store.get(blocks, file)
}

pub fn tampered_or_incomplete_inputs_fail_before_execution_test() {
  let prepared = environment.seal(environment(), sha256.hash)
  let corrupt =
    bundle.Bundle(
      ..prepared,
      store: dict.insert(prepared.store, prepared.root, <<"{}">>),
    )
  let assert Error(_) =
    bundle.from_string(bundle.to_string(corrupt), sha256.hash)
  let incomplete =
    bundle.Bundle(..prepared, store: dict.delete(prepared.store, prepared.root))
  let assert Error(_) =
    bundle.from_string(bundle.to_string(incomplete), sha256.hash)
}

pub fn output_identity_changes_with_contents_and_forks_share_inputs_test() {
  let base = environment()
  let first = virtual.fork(base)
  let second = virtual.fork(base)
  let assert #(sandbox.Returned(#(Ok(Ok(_)), changed)), _) =
    virtual.run(system.write_file("a", "different"), first)
    |> sandbox.run(sandbox.sandbox())
  assert fs.read(second.file_system, "/workspace/a") == Ok("same")
  let original = environment.seal(base, sha256.hash)
  let output =
    environment.seal(
      environment.Environment(..base, files: changed.file_system),
      sha256.hash,
    )
  assert output.root != original.root
  assert fs.read(base.files, "/workspace/a") == Ok("same")
}
