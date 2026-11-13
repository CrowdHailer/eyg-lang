import cloud/api
import cloud/artifacts
import cloud/channel
import cloud/instance
import cloud/operation
import cloud/plugins/chat_input
import cloud/registry
import cloud/server
import cloud/test_helpers
import cloud/web/runner
import cloud/workspace
import gleam/erlang/process
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import howdy/testing
import simplifile

const cloud_file = "test/fixtures/cloud.eyg"

fn start() {
  let data = "/tmp/eyg-cloud-web-test-" <> string.inspect(process.self())
  let _ = simplifile.delete(data)
  let state = test_helpers.state()
  let assert Ok(cloud) = instance.load(cloud_file, state)
  let assert Ok(store) = artifacts.start("http://localhost")
  let entries = list.map(cloud.workspaces, fn(e) { #(e.name, e.file) })
  let shells = list.map(cloud.shells, fn(s) { s.0 })
  let assert Ok(registry) = registry.start(entries, shells, state, store, data)
  let assert [handle] = process.call(registry, 1000, registry.Workspaces)
  process.send(
    handle.workspace,
    workspace.SetApi(api.perform(registry, state, _)),
  )
  let web =
    runner.Context(
      registry:,
      instance: instance.loader(cloud_file, state),
      state:,
    )
  let app =
    server.app(server.Context(store, fn(_, _) { Error("none") }, Some(web)))
  #(app, web)
}

fn sign_in(app, name) {
  let response =
    testing.request(http.Post, "/login")
    |> testing.text_body("name=" <> name)
    |> testing.send(app)
  assert response.status == 303
  let assert Ok(cookie) = list.key_find(response.headers, "set-cookie")
  let assert [pair, ..] = string.split(cookie, ";")
  let assert [_, token] = string.split(pair, "=")
  token
}

fn call(app, token, operation, body) {
  let response =
    testing.request(http.Post, "/api/" <> operation)
    |> testing.cookie("eyg_session", token)
    |> testing.text_body(json.to_string(body))
    |> testing.send(app)
  #(response.status, testing.text(response))
}

pub fn the_first_person_is_the_admin_test() {
  let #(app, web) = start()
  let ada = sign_in(app, "ada")
  let bob = sign_in(app, "bob")
  let assert [ada_user, bob_user] =
    process.call(web.registry, 1000, registry.Users)
  assert ada_user.token == ada && ada_user.admin
  assert bob_user.token == bob && !bob_user.admin
  // People without a shell choose the first in cloud.eyg.
  assert bob_user.shell == "observer"
}

pub fn the_api_is_gated_by_the_shell_policy_test() {
  let #(app, _web) = start()
  let ada = sign_in(app, "ada")
  let bob = sign_in(app, "bob")
  assert call(app, ada, "Workspaces", json.null())
    == #(
      200,
      "{\"Ok\":[{\"file\":\"test/fixtures/chat_workspace.eyg\",\"name\":\"test\"}]}",
    )
  assert call(app, bob, "Workspaces", json.null()).0 == 200
  assert call(app, bob, "Secrets", json.string("test"))
    == #(403, "{\"error\":\"Effect Secrets is not allowed by policy\"}")
  assert call(app, ada, "Shells", json.null())
    == #(200, "{\"Ok\":[\"observer\",\"pure\"]}")
  assert call(app, "nope", "Shells", json.null()).0 == 401
}

pub fn unbound_shells_bind_to_channels_test() {
  let #(_app, web) = start()
  let assert Ok(_) = process.call(web.registry, 1000, registry.SignIn("ada", _))
  let assert Ok(bob) =
    process.call(web.registry, 1000, registry.SignIn("bob", _))
  // Without a chat connected there is no channel to bind to.
  let #(run, binding) =
    runner.run(
      web,
      bob,
      None,
      "perform Bind({workspace: \"test\", channel: \"general\"})",
      [],
    )
  assert binding == None
  let assert Ok(Some(_)) = run.result
  // The observer shell may only bind to #general.
  let #(run, binding) =
    runner.run(
      web,
      bob,
      None,
      "perform Bind({workspace: \"test\", channel: \"notes\"})",
      [],
    )
  assert binding == None
  assert string.inspect(run.result)
    |> string.contains("binding to #notes is not allowed")
}

pub fn bound_shells_run_as_the_channel_test() {
  let #(_app, web) = start()
  let assert [handle] = process.call(web.registry, 1000, registry.Workspaces)
  let posts = process.new_subject()
  let outbound =
    channel.Outbound(
      input_type: chat_input.input_type(),
      post: fn(conversation, text) {
        process.send(posts, #(conversation, text))
        Ok("m1")
      },
      channel_name: fn(_) { "general" },
      channels: fn() { Ok([#("C1", "general")]) },
    )
  process.send(handle.workspace, workspace.Connect("chat", outbound))
  let assert Ok(ada) =
    process.call(web.registry, 1000, registry.SignIn("ada", _))
  let #(_, binding) =
    runner.run(
      web,
      ada,
      None,
      "perform Bind({workspace: \"test\", channel: \"general\"})",
      [],
    )
  assert binding == Some(runner.Binding("test", "general"))
  // Unbound shells cannot post, bound shells post as the channel.
  let #(run, _) = runner.run(web, ada, None, "perform Post(\"hi\")", [])
  assert string.inspect(run.result)
    |> string.contains("Bind to a channel to post")
  let #(_, binding) = runner.run(web, ada, binding, "perform Post(\"hi\")", [])
  assert process.receive(posts, 1000)
    == Ok(#(channel.Conversation("chat", "C1", None), "hi"))
  assert binding == Some(runner.Binding("test", "general"))
}

pub fn adding_a_trigger_keeps_configured_triggers_test() {
  let #(_app, web) = start()
  let assert [handle] = process.call(web.registry, 1000, registry.Workspaces)
  let outbound =
    channel.Outbound(
      input_type: chat_input.input_type(),
      post: fn(_, _) { Ok("m1") },
      channel_name: fn(_) { "general" },
      channels: fn() { Ok([#("C1", "general")]) },
    )
  process.send(handle.workspace, workspace.Connect("chat", outbound))
  let assert Ok(ada) =
    process.call(web.registry, 1000, registry.SignIn("ada", _))
  let binding = Some(runner.Binding("test", "general"))
  // No event has reached #general yet, its configured triggers are still installed.
  let #(run, _) =
    runner.run(
      web,
      ada,
      binding,
      "let _ = perform AddTrigger({name: \"extra\", pattern: (_) -> { False({}) }, script: (_) -> { {} }})\nperform ListTriggers({})",
      [],
    )
  let assert Ok(Some(listed)) = run.result
  let listed = string.inspect(listed)
  assert string.contains(listed, "summarise-links")
  assert string.contains(listed, "extra")
}

pub fn failed_policy_write_keeps_the_active_policy_test() {
  let #(_app, web) = start()
  let assert Ok(user) =
    process.call(web.registry, 1000, registry.SignIn("ada", _))
  let file =
    "/tmp/eyg-cloud-web-test-"
    <> string.inspect(process.self())
    <> "/users.json"
  let assert Ok(_) = simplifile.delete(file)
  let assert Ok(_) = simplifile.create_directory(file)
  let assert Error(_) =
    process.call(web.registry, 1000, registry.SetUserShell("ada", "pure", _))
  assert process.call(web.registry, 1000, registry.Users) == [user]
  let assert Ok(_) = simplifile.delete(file)
}

pub fn invalid_uploaded_channel_handlers_and_policies_keep_the_previous_source_test() {
  let #(_app, web) = start()
  let assert [handle] = process.call(web.registry, 1000, registry.Workspaces)
  let outbound =
    channel.Outbound(
      input_type: chat_input.input_type(),
      post: fn(_, _) { panic as "validation must not post" },
      channel_name: fn(_) { "general" },
      channels: fn() { Ok([#("C1", "general")]) },
    )
  process.send(handle.workspace, workspace.Connect("chat", outbound))
  let assert Ok(original) = simplifile.read(handle.file)
  list.each(
    [
      string.replace(
        original,
        "handle: cloud.handlers.for_channel(info)",
        "handle: (_) -> { 42 }",
      ),
      string.replace(
        original,
        "cloud.shell.everything",
        "{post: (_) -> { Pass(42) }, ..cloud.reject_all}",
      ),
    ],
    fn(source) {
      assert source != original
      let assert Error(_) =
        api.perform(
          web.registry,
          web.state,
          operation.SetWorkspaceSource("test", source),
        )
      assert simplifile.read(handle.file) == Ok(original)
    },
  )
}
