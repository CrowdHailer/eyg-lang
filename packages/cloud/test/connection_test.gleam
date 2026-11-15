import api_test
import cloud/access
import cloud/beam/execute
import cloud/beam/file_system
import cloud/box
import cloud/box/transaction as tx
import cloud/catalog
import cloud/connections
import cloud/overlay
import cloud/session
import cloud/slack/event
import cloud/templates
import gleam/bit_array
import gleam/erlang/process
import gleam/http/response
import gleam/string
import gleeunit/should

pub fn shell_and_channel_policy_test() {
  let #(service, _) = api_test.setup()
  let assert Ok(template) = templates.get("agent-notebook")
  let assert Ok(owner) =
    catalog.create(service.catalog, "notebook", template.files)
  box.connect(
    owner,
    "/system/connection.eyg",
    "user",
    "!int_add(2, 3)",
    service.agent,
  )
  |> should.equal(Ok("5"))
  let before = box.inspect(owner).files.root
  let assert Ok(_) =
    box.commit(
      owner,
      before,
      [
        tx.MakeDirectory("/system/connections"),
        templates.file(
          "/system/connections/slack-team-channel.eyg",
          "{mode: \"shell\", policy: import \"/system/policy.eyg\"}",
        ),
        tx.MakeDirectory("/system/events"),
        templates.file(
          "/system/events/slack-team-channel.eyg",
          "{handler: (input) -> { let _ = match input.event { MessageCreate(message) -> { perform AppendFile({path: \"/data/messages.txt\", contents: !string_to_binary(message.content)}) } } {} }, policy: import \"/system/policy.eyg\"}",
        ),
      ],
      fn(_) { True },
    )
  connections.dispatch(
    service,
    session.Incoming(
      "Slack:team:channel",
      event.to_eyg("general", event.MessageCreate("1", "channel", "hello", "1")),
    ),
  )
  file_system.read(box.inspect(owner).files, "/data/messages.txt", 0, 100)
  |> should.equal(Ok(<<"hello":utf8>>))
  let reply = process.new_subject()
  connections.dispatch(
    service,
    session.Message(
      "Slack:team:channel",
      session.Code(
        "perform WriteFile({path: \"/system/policy.eyg\", contents: !string_to_binary(\"{}\")})",
      ),
      process.send(reply, _),
    ),
  )
  let assert Ok(execute.StandardOut(text)) = process.receive(reply, 1000)
  string.contains(text, "Only /data/ is writable") |> should.be_true
}

pub fn agent_trajectory_persisted_test() {
  let #(service, _) = api_test.setup()
  let assert Ok(template) = templates.get("agent-notebook")
  let assert Ok(owner) =
    catalog.create(service.catalog, "agent", template.files)
  let before = box.inspect(owner).files.root
  box.commit(
    owner,
    before,
    [
      templates.file(
        "/system/connection.eyg",
        "{mode: \"agent\", policy: import \"/system/policy.eyg\"}",
      ),
    ],
    fn(_) { True },
  )
  |> should.be_ok
  let agent =
    overlay.Session(..service.agent, fetch: fn(_) {
      Ok(
        response.new(200)
        |> response.set_body(<<
          "{\"message\":{\"role\":\"assistant\",\"content\":\"Hello notebook\"},\"done\":true}":utf8,
        >>),
      )
    })
  let identity = access.token_id("test-user")
  box.connect(owner, "/system/connection.eyg", identity, "First turn", agent)
  |> should.equal(Ok("Hello notebook"))
  box.connect(owner, "/system/connection.eyg", identity, "Second turn", agent)
  |> should.equal(Ok("Hello notebook"))
  let assert Ok(bytes) =
    file_system.read(
      box.inspect(owner).files,
      "/traces/sessions/" <> identity <> ".json",
      0,
      10_000,
    )
  let assert Ok(text) = bit_array.to_string(bytes)
  string.contains(text, "First turn") |> should.be_true
  string.contains(text, "Second turn") |> should.be_true
}

pub fn channel_workspace_isolation_test() {
  let #(service, _) = api_test.setup()
  let assert Ok(template) = templates.get("agent-notebook")
  let assert Ok(owner) =
    catalog.create(service.catalog, "scoped", template.files)
  let root = box.inspect(owner).files.root
  box.commit(
    owner,
    root,
    [
      tx.MakeDirectory("/slack/channel/one"),
      tx.MakeDirectory("/app/skills"),
      templates.file("/app/skills/readme.txt", "instructions"),
      templates.file(
        "/system/policy.eyg",
        templates.channel_policy("/slack/channel/one"),
      ),
    ],
    fn(_) { True },
  )
  |> should.be_ok
  box.connect(
    owner,
    "/system/connection.eyg",
    "user",
    "perform WriteFile({path: \"/slack/channel/one/note.txt\", contents: !string_to_binary(\"saved\")})",
    service.agent,
  )
  |> should.equal(Ok("Ok({})"))
  let assert Ok(result) =
    box.connect(
      owner,
      "/system/connection.eyg",
      "user",
      "perform WriteFile({path: \"/slack/channel/one/../two/note.txt\", contents: !string_to_binary(\"denied\")})",
      service.agent,
    )
  string.contains(result, "Outside channel workspace") |> should.be_true
  let assert Ok(result) =
    box.connect(
      owner,
      "/system/connection.eyg",
      "user",
      "perform ReadFile({path: \"/app/skills/readme.txt\", offset: 0, limit: 100})",
      service.agent,
    )
  string.contains(result, "Ok(") |> should.be_true
}
