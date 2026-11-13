import gleam/dict
import gleam/option.{None}
import loam/sandbox
import loam/sandbox/fs
import loam/system
import loam/virtual
import simplifile

fn machine() {
  virtual.new("/p", 1000, 42)
  |> virtual.with_file("/p/snap.txt", virtual.Present(<<"snapshot">>))
}

fn host() {
  sandbox.sandbox()
  |> sandbox.with_file("/p/snap.txt", "host changed")
  |> sandbox.with_file("/p/hidden.txt", "host only")
  |> sandbox.with_env("HOST_TOKEN", "host secret")
}

fn run(effect) {
  let assert #(sandbox.Returned(#(Ok(value), machine)), host) =
    virtual.run(effect, machine()) |> sandbox.run(host())
  #(value, machine, host)
}

pub fn host_files_environment_and_listings_are_invisible_test() {
  let workflow = {
    use known <- system.then(system.read_file("snap.txt"))
    use unknown <- system.then(system.read_file_range("hidden.txt", 0, 100))
    use info <- system.then(system.file_info("hidden.txt"))
    use entries <- system.then(system.read_directory("/p"))
    use token <- system.map(system.env("HOST_TOKEN"))
    #(known, unknown, info, entries, token)
  }
  let #(value, _, _) = run(workflow)
  assert value
    == #(
      Ok("snapshot"),
      Error(simplifile.Enoent),
      Error(simplifile.Enoent),
      Ok(["snap.txt"]),
      None,
    )
}

pub fn independent_forks_and_host_are_unchanged_test() {
  let workflow = {
    use _ <- system.then(system.append_file_bits("snap.txt", <<"+fork">>))
    system.read_file("snap.txt")
  }
  let #(read, machine, host) = run(workflow)
  assert read == Ok("snapshot+fork")
  assert dict.get(virtual.changed(machine), "/p/snap.txt")
    == Ok(virtual.Present(<<"snapshot+fork">>))
  assert fs.read(host.file_system, "/p/snap.txt") == Ok("host changed")
  let #(read, _, _) = run(system.read_file("snap.txt"))
  assert read == Ok("snapshot")
}

pub fn nested_directories_deletion_and_errors_are_consistent_test() {
  let workflow = {
    use missing_parent <- system.then(
      system.write_file_bits("missing/a", <<"x">>),
    )
    use _ <- system.then(system.create_directory("/p/nested/deep"))
    use _ <- system.then(system.write_file_bits("nested/deep/a", <<"x">>))
    use nested <- system.then(system.read_directory("nested"))
    use _ <- system.then(system.delete_file("nested"))
    use after <- system.then(system.file_info("nested/deep/a"))
    use negative <- system.map(system.read_file_range("snap.txt", -1, 2))
    #(missing_parent, nested, after, negative)
  }
  let #(value, _, _) = run(workflow)
  assert value
    == #(
      Error(simplifile.Enoent),
      Ok(["deep"]),
      Error(simplifile.Enoent),
      Error(simplifile.Einval),
    )
}

pub fn clock_only_advances_on_sleep_and_random_is_fork_local_test() {
  let workflow = {
    use a <- system.then(system.now())
    use _ <- system.then(system.stdout("instrumentation"))
    use b <- system.then(system.now())
    use _ <- system.then(system.wait(5))
    use c <- system.then(system.now())
    use x <- system.map(system.random(100))
    #(a, b, c, x)
  }
  let #(first, _, _) = run(workflow)
  let #(second, _, _) = run(workflow)
  assert first == second
  let #(a, b, c, _) = first
  assert #(a, b, c) == #(1000, 1000, 1005)
}

pub fn quotas_stop_execution_before_an_output_or_write_test() {
  let limits =
    virtual.Limits(..virtual.limits(), written_bytes: 2, output_bytes: 2)
  let machine = virtual.Machine(..machine(), limits:)
  let assert #(sandbox.Returned(#(Error(_), machine)), _) =
    virtual.run(system.write_file_bits("snap.txt", <<"too big">>), machine)
    |> sandbox.run(host())
  assert fs.read(machine.file_system, "/p/snap.txt") == Ok("snapshot")
  let assert #(sandbox.Returned(#(Error(_), machine)), _) =
    virtual.run(system.stdout("too big"), machine) |> sandbox.run(host())
  assert machine.output == []
}

pub fn effects_are_bounded_and_exit_cannot_terminate_the_host_test() {
  let machine =
    virtual.Machine(
      ..machine(),
      limits: virtual.Limits(..virtual.limits(), effects: 1),
    )
  let workflow = {
    use _ <- system.then(system.now())
    system.now()
  }
  let assert #(sandbox.Returned(#(Error(_), _)), _) =
    virtual.run(workflow, machine) |> sandbox.run(host())
  let assert #(sandbox.Returned(#(Error(_), _)), _) =
    virtual.run(system.exit(0), machine) |> sandbox.run(host())
  let assert #(sandbox.Returned(#(Error(_), _)), _) =
    virtual.run(system.command("git", ["status"], "/p"), machine)
    |> sandbox.run(host())
}
