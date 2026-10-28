import eyg/cli/helpers
import eyg/cli/internal/traces
import eyg/cli/sandbox as runner
import glasshouse/archive
import glasshouse/bundle
import glasshouse/data
import glasshouse/session
import glasshouse/store
import gleam/bit_array
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import loam/broker
import loam/environment
import loam/sandbox
import loam/sandbox/fs

fn configuration() {
  let fields = [
    "acquire",
    "mount",
    "append_file",
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
  let policy =
    list.map(fields, fn(field) { field <> ": (request) -> { Pass(request) }" })
    |> string.join(",")
  "{llm: {provider: Ollama({origin: \"http://localhost:11434\", api_key: None({})}), model: \"scripted\"}, policy: {"
  <> policy
  <> "}, context: {readme: \"Acquire the input and read it\"}}"
}

const tool =
  "let receipt = match perform Acquire({source: Http({url: \"https://files.example.com/data\"}), expected: None({})}) {
  Ok(receipt) -> { receipt }
  Error(reason) -> { let _ = perform StandardError(reason) !never(perform Exit(1)) }
}
let mounted = perform Mount({root: receipt.root, path: \"download.txt\"})
let read = perform ReadFile({path: \"download.txt\", offset: 0, limit: 100})
{receipt, mounted, read}"

fn model(request: request.Request(BitArray), calls) {
  case request.host {
    "files.example.com" -> #(
      Ok(response.new(200) |> response.set_body(<<"acquired at runtime">>)),
      [request.host, ..calls],
    )
    _ -> {
      let assert Ok(body) = bit_array.to_string(request.body)
      let function =
        json.object([
          #("name", json.string("run")),
          #("arguments", json.object([#("code", json.string(tool))])),
        ])
      let message = case string.contains(body, "\"role\":\"tool\"") {
        True ->
          json.object([
            #("role", json.string("assistant")),
            #("content", json.string("Read the acquired input.")),
          ])
        False ->
          json.object([
            #("role", json.string("assistant")),
            #("content", json.string("")),
            #(
              "tool_calls",
              json.preprocessed_array([json.object([#("function", function)])]),
            ),
          ])
      }
      let body = json.to_string(json.object([#("message", message)]))
      #(Ok(response.new(200) |> response.set_body(<<body:utf8>>)), [
        request.host,
        ..calls
      ])
    }
  }
}

pub fn configuration_only_agent_acquires_mounts_exports_and_replays_offline_test() {
  let host =
    sandbox.sandbox()
    |> sandbox.with_file("/agent.eyg", configuration())
    |> sandbox.with_file("/host-only", "must not be mounted")
    |> sandbox.with_now(1000)
    |> sandbox.with_random_values([7])
    |> sandbox.with_network(model, [])
  let assert #(sandbox.Returned(Ok(0)), host) =
    runner.start(
      "/agent.eyg",
      "/runs",
      "get the input",
      ["localhost", "files.example.com"],
      helpers.config,
    )
    |> sandbox.run(host)
  assert host.network_state == ["localhost", "files.example.com", "localhost"]
  let assert Ok(names) = fs.read_directory(host.file_system, "/runs")
  let assert [name] = list.filter(names, string.ends_with(_, ".json"))
  let assert #(sandbox.Returned(Ok(archive)), _) =
    traces.load("/runs/" <> name) |> sandbox.run(host)
  assert runner.status(archive) == 0
  let assert Ok(#(input, observations)) = runner.inputs(archive)
  let assert Ok(initial) = environment.open(input)
  assert fs.read_directory(initial.files, "/workspace") == Ok([".overlay.eyg"])
  let assert [
    broker.Exchange(..),
    broker.Artifact(_, Ok(receipt)),
    broker.Exchange(..),
  ] = observations
  assert store.get_binary(archive.store, receipt.artifact.root)
    == Ok(<<"acquired at runtime">>)
  let assert Some(root) = archive.sandbox
  let assert Ok(descriptor) = store.get_node(archive.store, root)
  let assert Ok(output) =
    data.field(descriptor, "output") |> result.try(data.reference)
  let assert Ok(final) = environment.open(bundle.new(output, archive.store))
  assert final.artifacts == [receipt.artifact.root]
  assert fs.read(final.files, "/workspace/download.txt")
    == Ok("acquired at runtime")
  assert archive.missing(archive) == []
  assert list.length(session.generations(archive.session)) == 2
  let offline =
    sandbox.sandbox()
    |> sandbox.with_file("/export.json", archive.to_string(archive))
  let assert #(sandbox.Returned(Ok(0)), _) =
    runner.replay("/export.json", helpers.config) |> sandbox.run(offline)
}
