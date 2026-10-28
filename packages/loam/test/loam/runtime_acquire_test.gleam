import glasshouse/bundle
import glasshouse/sha256
import glasshouse/store
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import loam/acquire
import loam/broker
import loam/environment
import loam/sandbox
import loam/sandbox/fs
import loam/system
import loam/virtual
import touch_grass/acquire as acquisition
import touch_grass/mount

fn input() {
  acquisition.Input(
    acquisition.Git("https://example.com/project.git", Some("master")),
    None,
  )
}

fn artifact(text) {
  let #(blocks, root) =
    environment.store_tree(
      fs.directory([#("file.txt", fs.file(text))]),
      store.new(),
      sha256.hash,
    )
  bundle.new(root, blocks)
}

fn environment() {
  environment.Environment(
    ..environment.new(),
    files: fs.directory([#("workspace", fs.directory([]))]),
  )
}

fn changing_repository(input: acquisition.Input) {
  use version <- system.map(system.random(2))
  let #(commit, text) = case version {
    0 -> #("commit-A", "A")
    _ -> #("commit-B", "B")
  }
  Ok(acquire.Receipt(input.source, commit, artifact(text)))
}

fn workflow() {
  use first <- system.then(system.acquire(input()))
  let assert Ok(first) = first
  use mounted <- system.then(system.mount(mount.Input(first.root, "first")))
  let assert Ok(_) = mounted
  use written <- system.then(system.write_file("first/file.txt", "private edit"))
  let assert Ok(_) = written
  let assert Ok(request) = request.to("https://example.com/status")
  use response <- system.then(system.fetch(request.set_body(request, <<>>)))
  let assert Ok(response) = response
  use second <- system.then(system.acquire(input()))
  let assert Ok(second) = second
  use conflict <- system.then(system.mount(mount.Input(second.root, "first")))
  let assert Error(_) = conflict
  use mounted <- system.then(system.mount(mount.Input(second.root, "second")))
  let assert Ok(_) = mounted
  use mounted <- system.then(system.mount(mount.Input(first.root, "original")))
  let assert Ok(_) = mounted
  use a <- system.then(system.read_file("first/file.txt"))
  use b <- system.then(system.read_file("second/file.txt"))
  use original <- system.map(system.read_file("original/file.txt"))
  #(first, second, response.body, a, b, original)
}

pub fn mutable_branches_are_observations_not_cache_keys_test() {
  let machine =
    virtual.fork(environment())
    |> virtual.with_broker(broker.Live(["git:example.com", "example.com"]))
  let machine = virtual.Machine(..machine, fetcher: changing_repository)
  let host =
    sandbox.sandbox()
    |> sandbox.with_random_values([0, 1])
    |> sandbox.with_network(
      fn(_, calls) {
        #(Ok(response.new(200) |> response.set_body(<<"status">>)), calls + 1)
      },
      0,
    )
  let assert #(sandbox.Returned(#(Ok(result), machine)), host) =
    virtual.run(workflow(), machine) |> sandbox.run(host)
  let #(a, b, body, edited, latest, original) = result
  assert a.resolved == "commit-A"
  assert b.resolved == "commit-B"
  assert a.root != b.root
  assert #(body, edited, latest, original)
    == #(<<"status">>, Ok("private edit"), Ok("B"), Ok("A"))
  assert host.random_values == []
  assert host.network_state == 1
  let assert [
    broker.Artifact(key: first, ..),
    broker.Exchange(..),
    broker.Artifact(key: second, ..),
  ] = broker.journal(machine.broker)
  assert first == second

  // Transport only the journal's closure, then remove all live capabilities.
  let #(blocks, root) = broker.save(machine.broker, store.new())
  let assert Ok(transported) =
    bundle.from_string(bundle.to_string(bundle.new(root, blocks)), sha256.hash)
  let assert Ok(observations) = broker.load(transported.root, transported.store)
  let replay =
    virtual.fork(environment())
    |> virtual.with_broker(broker.Replay(observations))
  let replay =
    virtual.Machine(..replay, fetcher: fn(_) {
      panic as "replay called a fetcher"
    })
  let assert #(sandbox.Returned(#(Ok(repeated), replay)), _) =
    virtual.run(workflow(), replay) |> sandbox.run(sandbox.sandbox())
  assert repeated == result
  assert replay.file_system == machine.file_system
}

pub fn artifact_handles_survive_environment_export_without_mounting_test() {
  let machine =
    virtual.fork(environment())
    |> virtual.with_broker(broker.Live(["git:example.com"]))
  let machine = virtual.Machine(..machine, fetcher: changing_repository)
  let assert #(sandbox.Returned(#(Ok(Ok(receipt)), machine)), _) =
    virtual.run(system.acquire(input()), machine)
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_random_values([0]))
  assert fs.read_directory(machine.file_system, "/workspace") == Ok([])
  let saved =
    environment.seal(
      environment.Environment(
        ..environment(),
        files: machine.file_system,
        store: machine.artifact_store,
        artifacts: machine.artifact_roots,
      ),
      sha256.hash,
    )
  let assert Ok(restored) =
    bundle.from_string(bundle.to_string(saved), sha256.hash)
  let assert Ok(restored) = environment.open(restored)
  let machine = virtual.fork(restored)
  let workflow = {
    use mounted <- system.then(
      system.mount(mount.Input(receipt.root, "retained")),
    )
    let assert Ok(_) = mounted
    system.read_file("retained/file.txt")
  }
  let assert #(sandbox.Returned(#(Ok(Ok("A")), _)), _) =
    virtual.run(workflow, machine) |> sandbox.run(sandbox.sandbox())
}

pub fn git_and_http_grants_are_distinct_and_refusal_replays_test() {
  let machine =
    virtual.fork(environment())
    |> virtual.with_broker(broker.Live(["example.com"]))
  let machine =
    virtual.Machine(..machine, fetcher: fn(_) {
      panic as "unauthorised acquisition"
    })
  let assert #(sandbox.Returned(#(Error(reason), machine)), _) =
    virtual.run(system.acquire(input()), machine)
    |> sandbox.run(sandbox.sandbox())
  let replay =
    virtual.fork(environment())
    |> virtual.with_broker(broker.Replay(broker.journal(machine.broker)))
  let assert #(sandbox.Returned(#(Error(same), _)), _) =
    virtual.run(system.acquire(input()), replay)
    |> sandbox.run(sandbox.sandbox())
  assert same == reason
}

pub fn unchanged_branch_still_resolves_twice_but_stores_one_artifact_test() {
  let machine =
    virtual.fork(environment())
    |> virtual.with_broker(broker.Live(["git:example.com"]))
  let machine = virtual.Machine(..machine, fetcher: changing_repository)
  let workflow = {
    use first <- system.then(system.acquire(input()))
    use second <- system.map(system.acquire(input()))
    #(first, second)
  }
  let assert #(sandbox.Returned(#(Ok(#(first, second)), machine)), host) =
    virtual.run(workflow, machine)
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_random_values([0, 0]))
  assert first == second
  assert host.random_values == []
  assert list.length(machine.artifact_roots) == 1
  assert list.length(broker.journal(machine.broker)) == 2
}

pub fn cleanup_runs_when_git_fails_test() {
  let input =
    acquisition.Input(
      acquisition.Git("/missing-repository", Some("master")),
      None,
    )
  let assert #(sandbox.Returned(Error(_)), host) =
    acquire.perform(input) |> sandbox.run(sandbox.sandbox())
  assert fs.read_directory(host.file_system, "/tmp") == Ok([])
}

pub fn over_budget_acquisitions_record_errors_without_the_rejected_blocks_test() {
  let machine =
    virtual.fork(environment())
    |> virtual.with_broker(broker.Live(["git:example.com"]))
  let machine =
    virtual.Machine(
      ..machine,
      fetcher: changing_repository,
      limits: virtual.Limits(..virtual.limits(), written_bytes: 1),
    )
  let workflow = {
    use first <- system.then(system.acquire(input()))
    use second <- system.map(system.acquire(input()))
    #(first, second)
  }
  let assert #(sandbox.Returned(#(Ok(#(Ok(first), Error(reason))), machine)), _) =
    virtual.run(workflow, machine)
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_random_values([0, 1]))
  assert machine.artifact_roots == [first.root]
  let #(blocks, root) = broker.save(machine.broker, store.new())
  assert !store.has(blocks, artifact("B").root)
  let assert Ok(observations) = broker.load(root, blocks)
  let replay =
    virtual.fork(environment())
    |> virtual.with_broker(broker.Replay(observations))
  let assert #(sandbox.Returned(#(Ok(#(Ok(_), Error(same))), _)), _) =
    virtual.run(workflow, replay) |> sandbox.run(sandbox.sandbox())
  assert same == reason
}

pub fn expected_tree_mismatch_is_recorded_as_an_acquisition_failure_test() {
  let input =
    acquisition.Input(
      acquisition.Http("https://example.com/blob"),
      Some("wrong-root"),
    )
  let machine =
    virtual.fork(environment())
    |> virtual.with_broker(broker.Live(["example.com"]))
  let host =
    sandbox.sandbox()
    |> sandbox.with_network(
      fn(_, _) {
        #(Ok(response.new(200) |> response.set_body(<<"bytes">>)), Nil)
      },
      Nil,
    )
  let assert #(sandbox.Returned(#(Ok(Error(reason)), machine)), _) =
    virtual.run(system.acquire(input), machine) |> sandbox.run(host)
  let replay =
    virtual.fork(environment())
    |> virtual.with_broker(broker.Replay(broker.journal(machine.broker)))
  let assert #(sandbox.Returned(#(Ok(Error(same)), _)), _) =
    virtual.run(system.acquire(input), replay) |> sandbox.run(sandbox.sandbox())
  assert same == reason
}
