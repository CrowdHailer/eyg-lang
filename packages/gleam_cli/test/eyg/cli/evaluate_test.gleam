import eyg/cli/evaluate
import eyg/cli/helpers
import eyg/cli/internal/traces
import eyg/cli/sandbox as runner
import glasshouse/archive
import glasshouse/bundle
import glasshouse/cohort
import glasshouse/data
import glasshouse/session
import glasshouse/store
import gleam/bit_array
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import loam/acquire
import loam/broker
import loam/environment
import loam/prepare
import loam/sandbox
import loam/sandbox/fs
import loam/source

const fields = [
  "append_file",
  "acquire",
  "mount",
  "create_key",
  "cwd",
  "delete_file",
  "env",
  "exit",
  "fetch",
  "flip",
  "make_directory",
  "now",
  "random",
  "read_directory",
  "read_file",
  "sleep",
  "standard_error",
  "standard_in",
  "standard_out",
  "write_file",
]

fn configuration() {
  let policy =
    list.map(fields, fn(field) { field <> ": (x) -> { Pass(x) }" })
    |> string.join(",")
  "let readme = match perform ReadFile({path: \"README.md\", offset: 0, limit: 10000}) {
    Ok(bytes) -> { match !string_from_binary(bytes) { Ok(text) -> { text } Error(_) -> { \"\" } } }
    Error(_) -> { \"\" }
  }
{llm: {provider: Ollama({origin: \"http://localhost:11434\", api_key: None({})}), model: \"test-model\"}, policy: {"
  <> policy
  <> "}, context: {readme}}"
}

const edit =
  "let _ = perform AppendFile({path: \"notes.txt\", contents: !string_to_binary(\"line three\\n\")})
perform ReadFile({path: \"notes.txt\", offset: 0, limit: 1000})"

fn model(request: request.Request(BitArray), calls) {
  let assert Ok(body) = bit_array.to_string(request.body)
  let message = case string.contains(body, "\"role\":\"tool\"") {
    True ->
      json.object([
        #("role", json.string("assistant")),
        #("content", json.string("Done.")),
      ])
    False -> {
      let function =
        json.object([
          #("name", json.string("run")),
          #("arguments", json.object([#("code", json.string(edit))])),
        ])
      json.object([
        #("role", json.string("assistant")),
        #("content", json.string("")),
        #(
          "tool_calls",
          json.preprocessed_array([json.object([#("function", function)])]),
        ),
      ])
    }
  }
  let body =
    json.to_string(
      json.object([
        #("message", message),
        #("prompt_eval_count", json.int(100)),
        #("eval_count", json.int(20)),
      ]),
    )
  #(Ok(response.new(200) |> response.set_body(<<body:utf8>>)), [
    request.path,
    ..calls
  ])
}

pub fn recorded() {
  let host =
    sandbox.sandbox()
    |> sandbox.with_files([
      #("/project/.overlay.eyg", configuration()),
      #("/project/README.md", "# Project"),
      #("/project/notes.txt", "line one\nline two\n"),
    ])
    |> sandbox.with_network(model, [])
  let assert #(sandbox.Returned(Ok(tree)), host) =
    acquire.local("/project", [], traces.sha256) |> sandbox.run(host)
  let assert #(sandbox.Returned(Ok(input)), host) =
    prepare.prepare(
      tree,
      ".overlay.eyg",
      helpers.config.client.origin,
      traces.sha256,
    )
    |> sandbox.run(host)
  let assert #(sandbox.Returned(Ok(archive)), host) =
    runner.run(
      input,
      ".overlay.eyg",
      runner.Agent,
      ["add a line"],
      broker.Live(["localhost"]),
      "baseline",
      helpers.config,
    )
    |> sandbox.run(host)
  assert cohort.stopped(archive.session) == None
  assert list.length(session.generations(archive.session)) == 2
  #(archive, host)
}

pub fn sandbox_agent_does_not_modify_host_and_full_replay_is_offline_test() {
  let #(archive, host) = recorded()
  assert fs.read(host.file_system, "/project/notes.txt")
    == Ok("line one\nline two\n")
  let host =
    sandbox.sandbox()
    |> sandbox.with_cwd("/other-machine")
    |> sandbox.with_file("/trace.json", archive.to_string(archive))
  let assert #(sandbox.Returned(Ok(0)), _) =
    runner.replay("/trace.json", helpers.config) |> sandbox.run(host)
}

pub fn identical_fork_recomputes_files_and_reuses_ordered_external_prefix_test() {
  let #(archive, _) = recorded()
  let assert Ok(#(input, observations)) = runner.inputs(archive)
  let assert #(sandbox.Returned(Ok(fork)), _) =
    runner.run(
      input,
      ".overlay.eyg",
      runner.Agent,
      ["add a line"],
      broker.Fork(observations, []),
      "fork",
      helpers.config,
    )
    |> sandbox.run(sandbox.sandbox())
  assert cohort.stopped(fork.session) == None
  assert fork.sandbox == archive.sandbox
  assert runner.summarize("fork", fork).recorded == 2
  assert runner.summarize("fork", fork).live == session.Usage(0, 0)
  assert runner.summarize("fork", fork).changes
    == [cohort.Change("/workspace/notes.txt", 1, 0)]
}

pub fn changed_files_diverge_and_require_explicit_live_model_permission_test() {
  let #(archive, _) = recorded()
  let assert Ok(#(input, observations)) = runner.inputs(archive)
  let variant = evaluate.Variant("brief", [#("README.md", "Be brief")], None)
  let assert Ok(changed) = evaluate.reproduction(input, variant)
  let assert #(sandbox.Returned(Ok(stopped)), _) =
    runner.run(
      changed,
      ".overlay.eyg",
      runner.Agent,
      ["add a line"],
      broker.Fork(observations, []),
      "stopped",
      helpers.config,
    )
    |> sandbox.run(sandbox.sandbox())
  let assert Some(_) = cohort.stopped(stopped.session)
  let host = sandbox.sandbox() |> sandbox.with_network(model, [])
  let assert #(sandbox.Returned(Ok(fork)), host) =
    runner.run(
      changed,
      ".overlay.eyg",
      runner.Agent,
      ["add a line"],
      broker.Fork(observations, ["localhost"]),
      "live",
      helpers.config,
    )
    |> sandbox.run(host)
  assert cohort.stopped(fork.session) == None
  assert host.network_state == ["/api/chat", "/api/chat"]
}

pub fn shared_storage_exports_a_portable_verified_archive_test() {
  let #(archive, _) = recorded()
  let assert #(sandbox.Returned(Ok(path)), host) =
    traces.save_shared(archive, "/traces") |> sandbox.run(sandbox.sandbox())
  let assert Ok(manifest) = fs.read(host.file_system, path)
  let assert Ok(metadata) = archive.from_string(manifest)
  assert store.to_list(metadata.store) == []
  let assert #(sandbox.Returned(Ok(loaded)), host) =
    traces.load(path) |> sandbox.run(host)
  assert loaded == archive
  let assert #(sandbox.Returned(Ok(0)), host) =
    runner.export(path, "/portable.json") |> sandbox.run(host)
  let assert Ok(portable) = fs.read(host.file_system, "/portable.json")
  let fresh = sandbox.sandbox() |> sandbox.with_file("/portable.json", portable)
  let assert #(sandbox.Returned(Ok(0)), _) =
    runner.replay("/portable.json", helpers.config) |> sandbox.run(fresh)
}

pub fn evaluate_requires_a_complete_environment_test() {
  let #(archive, _) = recorded()
  let legacy = archive.Archive(..archive, sandbox: None)
  let assert Error(_) = runner.inputs(legacy)
}

pub fn initial_tree_survives_write_without_prior_read_test() {
  let #(archive, _) = recorded()
  let assert Ok(#(input, _)) = runner.inputs(archive)
  let assert Ok(initial) = environment.open(input)
  assert fs.read(initial.files, "/workspace/notes.txt")
    == Ok("line one\nline two\n")
  let assert Some(root) = archive.sandbox
  let assert Ok(descriptor) = store.get_node(archive.store, root)
  let assert Ok(output) =
    data.field(descriptor, "output") |> result.try(data.reference)
  let assert Ok(final) = environment.open(bundle.new(output, archive.store))
  assert fs.read(final.files, "/workspace/notes.txt")
    == Ok("line one\nline two\nline three\n")
}

pub fn evaluate_saves_cohorts_from_sealed_inputs_test() {
  let #(archive, _) = recorded()
  let host =
    sandbox.sandbox()
    |> sandbox.with_file("/traces/baseline.json", archive.to_string(archive))
    |> sandbox.with_network(model, [])
  let plan =
    "{hosts: [\"localhost\"], variants: [{name: \"same\", files: [], prompts: None({})}, {name: \"brief\", files: [{path: \"README.md\", contents: \"Be brief\"}], prompts: None({})}]}"
  let assert #(sandbox.Returned(Ok(0)), host) =
    evaluate.execute("/traces/baseline.json", source.Code(plan), helpers.config)
    |> sandbox.run(host)
  let assert Ok(report) =
    fs.read(host.file_system, "/traces/baseline.cohort.json")
  let assert Ok(#(_, [_, same, brief])) =
    json.parse(report, cohort.report_decoder())
  assert same.recorded == 2
  assert brief.recorded == 0
  assert host.network_state == ["/api/chat", "/api/chat"]
}

pub fn stopped_agent_keeps_model_cost_and_can_be_replayed_test() {
  let #(baseline, _) = recorded()
  let assert Ok(#(input, _)) = runner.inputs(baseline)
  let code =
    "perform Fetch({method: GET({}), scheme: HTTPS({}), host: \"denied.example\", port: None({}), path: \"/\", query: None({}), headers: [], body: !string_to_binary(\"\")})"
  let function =
    json.object([
      #("name", json.string("run")),
      #("arguments", json.object([#("code", json.string(code))])),
    ])
  let message =
    json.object([
      #("role", json.string("assistant")),
      #("content", json.string("")),
      #(
        "tool_calls",
        json.preprocessed_array([json.object([#("function", function)])]),
      ),
    ])
  let body =
    json.to_string(
      json.object([
        #("message", message),
        #("prompt_eval_count", json.int(100)),
        #("eval_count", json.int(20)),
      ]),
    )
  let host =
    sandbox.sandbox()
    |> sandbox.with_network(
      fn(_, _) {
        #(Ok(response.new(200) |> response.set_body(<<body:utf8>>)), Nil)
      },
      Nil,
    )
  let assert #(sandbox.Returned(Ok(stopped)), _) =
    runner.run(
      input,
      ".overlay.eyg",
      runner.Agent,
      ["fetch"],
      broker.Live(["localhost"]),
      "stopped",
      helpers.config,
    )
    |> sandbox.run(host)
  let summary = runner.summarize("stopped", stopped)
  assert summary.generations == 1
  assert summary.live == session.Usage(100, 20)
  let assert Some(_) = summary.stopped
  let host =
    sandbox.sandbox()
    |> sandbox.with_file("/trace.json", archive.to_string(stopped))
  let assert #(sandbox.Returned(Ok(0)), _) =
    runner.replay("/trace.json", helpers.config) |> sandbox.run(host)
}
