import cloud/access
import cloud/api
import cloud/beam/execute
import cloud/beam/file_system
import cloud/box
import cloud/catalog
import cloud/overlay
import cloud/templates
import eyg/hub/cache
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/http
import gleam/json
import gleeunit/should
import howdy
import howdy/testing
import multiformats/cid/v1
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama

pub fn setup() {
  let directory =
    "/tmp/opencode/cloud-api-"
    <> bit_array.base64_url_encode(crypto.strong_random_bytes(12), False)
  let runtime =
    execute.State(origin.http("localhost"), cache.ready(), dict.new())
  let assert Ok(catalog) = catalog.start(directory, runtime)
  let assert Ok(access) =
    access.start(directory <> "/account.json", "test-admin", runtime)
  let service =
    api.Service(
      catalog.data,
      access.data,
      overlay.setup(
        runtime.origin,
        provider.Llm(provider.Ollama(ollama.local()), "test"),
      ),
    )
  #(
    service,
    howdy.new()
      |> howdy.controller(api.controller(service))
      |> howdy.controller(api.public_controller(service)),
  )
}

pub fn webhook_cron_fork_and_conflict_test() {
  let #(service, app) = setup()
  let assert Ok(template) = templates.get("webhook-inbox")
  let assert Ok(owner) =
    catalog.create(service.catalog, "events", template.files)
  let before = box.inspect(owner).files.root
  let res =
    testing.request(http.Post, "/app/events/hook")
    |> testing.bytes_body(<<"payload":utf8>>)
    |> testing.send(app)
  res.status |> should.equal(200)
  let files = box.inspect(owner).files
  file_system.read(files, "/data/events.ndjson", 0, 100)
  |> should.equal(Ok(<<"payload\n":utf8>>))
  let transaction =
    json.object([
      #("base", json.string(v1.to_string(before))),
      #("changes", json.array([], json.string)),
    ])
  let res =
    testing.post("/api/boxes/events/transactions", transaction)
    |> testing.header("authorization", "Bearer test-admin")
    |> testing.send(app)
  res.status |> should.equal(409)
  let assert Ok(fork) = catalog.fork(service.catalog, "copy", "events", before)
  file_system.read(box.inspect(fork).files, "/data/events.ndjson", 0, 100)
  |> should.be_error
  let assert Ok(template) = templates.get("cron-heartbeat")
  let assert Ok(owner) =
    catalog.create(service.catalog, "clock", template.files)
  let res =
    testing.post("/api/boxes/clock/cron/heartbeat/run", json.object([]))
    |> testing.header("authorization", "Bearer test-admin")
    |> testing.send(app)
  res.status |> should.equal(200)
  file_system.read(box.inspect(owner).files, "/data/heartbeats.txt", 0, 100)
  |> should.equal(Ok(<<"heartbeat\n":utf8>>))
}

pub fn scoped_tokens_and_revocation_test() {
  let #(service, app) = setup()
  let assert Ok(template) = templates.get("webhook-inbox")
  let assert Ok(owner) =
    catalog.create(service.catalog, "events", template.files)
  let assert Ok(token) =
    access.issue(
      service.access,
      "test-admin",
      "events",
      "(request) -> { !string_starts_with(request.path, \"/data/\") }",
    )
  let root = box.inspect(owner).files.root |> v1.to_string
  let res =
    testing.request(http.Put, "/api/boxes/events/files/data/note.txt")
    |> testing.bytes_body(<<"note":utf8>>)
    |> testing.header("authorization", "Bearer " <> token)
    |> testing.header("if-match", root)
    |> testing.send(app)
  res.status |> should.equal(200)
  let res =
    testing.get("/api/boxes/events/files/system/policy.eyg")
    |> testing.header("authorization", "Bearer " <> token)
    |> testing.send(app)
  res.status |> should.equal(403)
  let res =
    testing.get("/api/boxes")
    |> testing.header("authorization", "Bearer " <> token)
    |> testing.send(app)
  res.status |> should.equal(403)
  access.revoke(service.access, "test-admin", access.token_id(token))
  |> should.be_ok
  let res =
    testing.get("/api/boxes/events/files/data/note.txt")
    |> testing.header("authorization", "Bearer " <> token)
    |> testing.send(app)
  res.status |> should.equal(403)
  access.issue(service.access, "test-admin", "events", "42") |> should.be_error
}
