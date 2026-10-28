import eyg/cli/helpers
import eyg/cli/internal/traces
import eyg/cli/sandbox as runner
import eyg/interpreter/value as v
import glasshouse/archive
import glasshouse/run
import glasshouse/session
import glasshouse/value
import gleam/list
import loam/acquire
import loam/broker
import loam/prepare
import loam/sandbox
import loam/sandbox/fs

fn prepared(code) {
  let host =
    sandbox.sandbox()
    |> sandbox.with_files([
      #("/project/main.eyg", code),
      #(
        "/project/lib/read.eyg",
        "(_) -> { perform ReadFile({path: \"data.txt\", offset: 0, limit: 100}) }",
      ),
      #("/project/lib/data.txt", "sealed"),
    ])
  let assert #(sandbox.Returned(Ok(tree)), host) =
    acquire.local("/project", [], traces.sha256) |> sandbox.run(host)
  let assert #(sandbox.Returned(Ok(input)), _) =
    prepare.prepare(
      tree,
      "main.eyg",
      helpers.config.client.origin,
      traces.sha256,
    )
    |> sandbox.run(host)
  input
}

pub fn relative_imports_keep_virtual_locations_and_new_pure_effects_work_test() {
  let input =
    prepared(
      "let read = import \"lib/read.eyg\"
let data = read({})
let _ = perform Hash({algorithm: SHA256({}), bytes: !string_to_binary(\"new input\")})
let _ = perform DecodeJSON(!string_to_binary(\"42\"))
data",
    )
  let assert #(sandbox.Returned(Ok(archive)), _) =
    runner.run(
      input,
      "main.eyg",
      runner.Block,
      [],
      broker.Offline,
      "test",
      helpers.config,
    )
    |> sandbox.run(sandbox.sandbox())
  assert runner.status(archive) == 0
  let assert [run] = session.runs(archive.session)
  assert list.map(run.journal, fn(entry) { entry.label })
    == ["ReadFile", "Hash", "DecodeJSON"]
  let assert run.Returned(encoded) = run.outcome
  assert value.decode(encoded, archive.store, Nil)
    == Ok(v.ok(v.Binary(<<"sealed">>)))
  let host =
    sandbox.sandbox()
    |> sandbox.with_file("/trace.json", archive.to_string(archive))
  let assert #(sandbox.Returned(Ok(0)), _) =
    runner.replay("/trace.json", helpers.config) |> sandbox.run(host)
}

pub fn pure_runaway_fails_and_another_fork_can_finish_test() {
  let input = prepared("!fix((self, x) -> { self(x) })(0)")
  let assert #(sandbox.Returned(Ok(archive)), _) =
    runner.run(
      input,
      "main.eyg",
      runner.Block,
      [],
      broker.Offline,
      "runaway",
      helpers.config,
    )
    |> sandbox.run(sandbox.sandbox())
  assert runner.status(archive) == 1
  let input = prepared("42")
  let assert #(sandbox.Returned(Ok(archive)), _) =
    runner.run(
      input,
      "main.eyg",
      runner.Block,
      [],
      broker.Offline,
      "finite",
      helpers.config,
    )
    |> sandbox.run(sandbox.sandbox())
  assert runner.status(archive) == 0
}

pub fn host_reads_are_explicitly_missing_even_if_the_file_exists_test() {
  let input =
    prepared(
      "perform ReadFile({path: \"/host/secret\", offset: 0, limit: 100})",
    )
  let host = sandbox.sandbox() |> sandbox.with_file("/host/secret", "private")
  let assert #(sandbox.Returned(Ok(archive)), host) =
    runner.run(
      input,
      "main.eyg",
      runner.Block,
      [],
      broker.Offline,
      "missing",
      helpers.config,
    )
    |> sandbox.run(host)
  let assert [run.Run(outcome: run.Returned(encoded), ..)] =
    session.runs(archive.session)
  let assert Ok(v.Tagged("Error", _)) =
    value.decode(encoded, archive.store, Nil)
  assert fs.read(host.file_system, "/host/secret") == Ok("private")
}

pub fn refused_external_requests_are_reproducible_failures_test() {
  let input =
    prepared(
      "perform Fetch({method: GET({}), scheme: HTTPS({}), host: \"example.com\", port: None({}), path: \"/\", query: None({}), headers: [], body: !string_to_binary(\"\")})",
    )
  let assert #(sandbox.Returned(Ok(archive)), _) =
    runner.run(
      input,
      "main.eyg",
      runner.Block,
      [],
      broker.Offline,
      "refused",
      helpers.config,
    )
    |> sandbox.run(sandbox.sandbox())
  assert runner.status(archive) == 1
  let host =
    sandbox.sandbox()
    |> sandbox.with_file("/trace.json", archive.to_string(archive))
  let assert #(sandbox.Returned(Ok(0)), _) =
    runner.replay("/trace.json", helpers.config) |> sandbox.run(host)
}
