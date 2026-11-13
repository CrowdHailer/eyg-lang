//// Exercise the bundled public plugin with the official SDK's HTTP serializer.
//// The fetch service is deterministic; no model provider is contacted.

import envoy
import gleam/dynamic/decode
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/string
import javascript/mutable_reference as reference
import opencode_plugin/native as n
import opencode_plugin/sdk
import plinthx/browser/fetch
import plinthx/javascript/foreign
import plinthx/javascript/module
import plinthx/node/fs
import simplifile

const config =
  "{
  policy: {read_file: Pass, write_file: (_) -> { Mock(Error(\"read only\")) }, task: Pass, escalate: Pass},
  context: {answer: 42, readme: \"project instructions\"},
  agents: {writer: {read_file: Pass, write_file: Pass}}
}"

fn invoke(function, args) {
  foreign.apply(function, array.from_list(args)) |> foreign.to_promise
}

fn response(value, status) {
  let assert Ok(constructor) = fetch.get_response()
  let assert Ok(response) =
    fetch.new_response(constructor, value, status, [
      #("content-type", "application/json"),
    ])
  response
}

fn ctx(id, ask) {
  n.object([
    #("sessionID", n.data(id)),
    #(
      "agent",
      n.data(case id {
        "top" -> ""
        _ -> "writer"
      }),
    ),
    #("ask", n.data(ask)),
  ])
}

fn run(hooks, code, context) {
  n.call(n.field(n.field(hooks, "tool"), "eyg"), "execute", [
    n.object([#("code", n.data(code))]),
    context,
  ])
  |> foreign.to_promise
}

fn text(reply) {
  n.string(reply, "output")
}

fn with_fixture(check) {
  let before = envoy.get("OPENCODE_EYG_CONFIG")
  let assert Ok(root) = fs.temporary_directory("eyg-opencode-plugin-")
  let file = root <> "/config.eyg"
  envoy.set("OPENCODE_EYG_CONFIG", file)
  let assert Ok(_) = simplifile.write(file, config)
  let assert Ok(_) = simplifile.write(root <> "/notes.md", "# notes\n")
  let assert Ok(cwd) = simplifile.current_directory()
  use loaded <- promise.await(module.load(cwd <> "/dist/eyg.mjs"))
  let assert Ok(api) = loaded
  let hooks = reference.new(n.object([]))
  let events = reference.new([])
  let child_check = reference.new(fn(_, _) { promise.resolve(Nil) })
  let add = fn(event) {
    let _ = reference.set(events, list.append(reference.get(events), [event]))
    Nil
  }
  let client =
    sdk.create_client(
      n.object([
        #("baseUrl", n.data("http://fixture.invalid")),
        #("directory", n.data(root)),
        #(
          "fetch",
          n.data(fn(request) {
            let method = fetch.request_method(request)
            let url = fetch.request_url(request)
            case method {
              "GET" -> {
                add("get")
                assert string.contains(url, "/session/")
                promise.resolve(response("{\"id\":\"top\"}", 200))
              }
              "POST" -> {
                use body <- promise.await(fetch.request_text(request))
                let assert Ok(body) = body
                let assert Ok(body) = json.parse(body, decode.dynamic)
                case string.ends_with(url, "/session") {
                  True -> {
                    add("create")
                    assert n.string(body, "parentID") == "top"
                    promise.resolve(response(
                      "{\"id\":\"child\",\"parentID\":\"top\"}",
                      200,
                    ))
                  }
                  False -> {
                    add("prompt")
                    assert string.ends_with(url, "/session/child/message")
                    assert n.string(body, "agent") == "writer"
                    let assert [part] = n.list(n.field(body, "parts"))
                    assert n.string(part, "type") == "text"
                    assert n.string(part, "text") == "go"
                    let callback = reference.get(child_check)
                    use _ <- promise.map(callback(reference.get(hooks), root))
                    response(
                      "{\"parts\":[{\"type\":\"text\",\"text\":\"first\"},{\"type\":\"text\",\"text\":\"child finished\"}]}",
                      200,
                    )
                  }
                }
              }
              _ -> n.fail("unexpected SDK request")
            }
          }),
        ),
      ]),
    )
  use value <- promise.await(
    invoke(n.field(api, "EygPlugin"), [
      n.object([#("client", client), #("directory", n.data(root))]),
    ]),
  )
  let _ = reference.set(hooks, value)
  let checked =
    check(value, root, file, events, child_check, add)
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.map(checked)
  let assert Ok(_) = simplifile.delete(root)
  case before {
    Ok(value) -> envoy.set("OPENCODE_EYG_CONFIG", value)
    Error(_) -> envoy.unset("OPENCODE_EYG_CONFIG")
  }
  case checked {
    Ok(_) -> Nil
    Error(reason) -> foreign.raise(reason)
  }
}

fn no_approval(_) {
  n.fail("approval was not expected")
}

pub fn public_tool_schema_context_effects_and_prompt_test() {
  use hooks, root, _, _, _, _ <- with_fixture()
  // Seed the ordinary parent without a named-agent policy.
  let parent = n.object([#("sessionID", n.data("top"))])
  use _ <- promise.await(
    invoke(n.field(hooks, "chat.message"), [parent, n.object([])]),
  )
  let tool = n.field(n.field(hooks, "tool"), "eyg")
  let schema = n.field(n.field(tool, "args"), "code")
  assert n.call(schema, "parse", [n.data("42")]) == n.data("42")
  use answer <- promise.await(run(
    hooks,
    "context.answer",
    ctx("top", no_approval),
  ))
  assert text(answer) == "42"
  use read <- promise.await(run(
    hooks,
    "match perform ReadFile({path: \"notes.md\", offset: 0, limit: 100}) { Ok(bytes) -> { !string_from_binary(bytes) } Error(reason) -> { Error(reason) } }",
    ctx("top", no_approval),
  ))
  assert text(read) == "Ok(\"# notes\\n\")"
  use write <- promise.await(run(
    hooks,
    "perform WriteFile({path: \"out.txt\", contents: !string_to_binary(\"x\")})",
    ctx("top", no_approval),
  ))
  assert text(write) == "Error(\"read only\")"
  assert simplifile.is_file(root <> "/out.txt") == Ok(False)
  use denied <- promise.await(run(
    hooks,
    "perform Env(\"HOME\")",
    ctx("top", no_approval),
  ))
  assert string.contains(text(denied), "not allowed by your policy")
  let system = n.array([])
  use _ <- promise.map(
    invoke(n.field(hooks, "experimental.chat.system.transform"), [
      parent,
      n.object([#("system", system)]),
    ]),
  )
  let assert [prompt] = n.list(system)
  let prompt = n.text(prompt)
  assert string.contains(prompt, "project instructions")
  assert string.contains(prompt, "ReadFile(↑")
  assert string.contains(prompt, "Escalate:")
  assert !string.contains(prompt, "Env(↑")
  assert string.contains(prompt, "# EYG Syntax Guide")
  assert string.contains(prompt, "name: Builtins reference")
}

pub fn task_assigns_policy_before_first_and_later_child_calls_test() {
  use hooks, _, _, events, child_check, _ <- with_fixture()
  let child_check_fn = fn(hooks, root) {
    // A later hook naming a more privileged agent must retain the explicit policy.
    use _ <- promise.await(
      invoke(n.field(hooks, "chat.message"), [
        ctx("child", no_approval),
        n.object([]),
      ]),
    )
    use read <- promise.await(run(
      hooks,
      "perform ReadFile({path: \"notes.md\", offset: 0, limit: 100})",
      ctx("child", no_approval),
    ))
    assert n.field(n.field(read, "metadata"), "ok") == n.data(True)
    use denied <- promise.map(run(
      hooks,
      "perform WriteFile({path: \"out.txt\", contents: !string_to_binary(\"x\")})",
      ctx("child", no_approval),
    ))
    assert string.contains(text(denied), "not allowed by your policy")
    assert simplifile.is_file(root <> "/out.txt") == Ok(False)
  }
  let _ = reference.set(child_check, child_check_fn)
  use reply <- promise.await(run(
    hooks,
    "perform Task({agent: \"writer\", prompt: \"go\", policy: {read_file: Pass}})",
    ctx("top", no_approval),
  ))
  assert text(reply) == "Ok(\"child finished\")"
  assert reference.get(events) == ["get", "create", "prompt"]
  use denied <- promise.map(run(
    hooks,
    "perform Task({agent: \"writer\", prompt: \"go\", policy: {read_file: Pass}})",
    ctx("child", no_approval),
  ))
  assert string.contains(text(denied), "not allowed by your policy")
}

pub fn escalation_requires_approval_before_replacing_the_child_policy_test() {
  use hooks, root, _, events, child_check, add <- with_fixture()
  let parent = n.object([#("sessionID", n.data("top"))])
  use _ <- promise.await(
    invoke(n.field(hooks, "chat.message"), [parent, n.object([])]),
  )
  let code =
    "perform Escalate({agent: \"writer\", prompt: \"go\", policy: {write_file: Pass}})"
  let deny = fn(request) {
    assert n.string(request, "permission") == "eyg_escalate"
    add("denied")
    n.fail("permission refused")
  }
  use denied <- promise.await(run(hooks, code, ctx("top", deny)))
  assert string.contains(text(denied), "permission refused")
  assert reference.get(events) == ["get", "denied"]
  let _ =
    reference.set(child_check, fn(hooks, _) {
      use written <- promise.map(run(
        hooks,
        "perform WriteFile({path: \"out.txt\", contents: !string_to_binary(\"approved\")})",
        ctx("child", no_approval),
      ))
      assert text(written) == "Ok({})"
    })
  let approve = fn(request) {
    assert n.string(request, "permission") == "eyg_escalate"
    add("approved")
    promise.resolve(Nil)
  }
  use reply <- promise.map(run(hooks, code, ctx("top", approve)))
  assert text(reply) == "Ok(\"child finished\")"
  assert reference.get(events)
    == ["get", "denied", "approved", "create", "prompt"]
  assert simplifile.read(root <> "/out.txt") == Ok("approved")
}

pub fn changed_invalid_configuration_fails_closed_test() {
  use hooks, _, file, _, _, _ <- with_fixture()
  use answer <- promise.await(run(hooks, "42", ctx("top", no_approval)))
  assert text(answer) == "42"
  let assert Ok(_) = simplifile.write(file, "{policy: 42}")
  use invalid <- promise.map(
    run(hooks, "42", ctx("top", no_approval))
    |> promise.map(Ok)
    |> promise.rescue(Error),
  )
  let assert Error(reason) = invalid
  assert string.contains(
    n.string(reason, "message"),
    "Failed to load EYG configuration",
  )
}

pub fn an_unreadable_session_cannot_fall_back_to_top_level_policy_test() {
  use hooks, _, _, _, _, _ <- with_fixture()
  use reply <- promise.map(
    run(hooks, "42", ctx("missing", no_approval))
    |> promise.map(Ok)
    |> promise.rescue(Error),
  )
  let assert Error(reason) = reply
  assert n.string(reason, "message") == "failed to read session missing"
}

pub fn main() {
  use _ <- promise.await(public_tool_schema_context_effects_and_prompt_test())
  io.println(
    "PASS public EYG tool: real Zod schema, files, mocks, context and prompt guidance",
  )
  use _ <- promise.await(
    task_assigns_policy_before_first_and_later_child_calls_test(),
  )
  io.println(
    "PASS official SDK Task: child policy assigned before prompt, retained on later calls",
  )
  use _ <- promise.await(
    escalation_requires_approval_before_replacing_the_child_policy_test(),
  )
  io.println(
    "PASS Escalate: refused permission creates no session; approval replaces child policy",
  )
  use _ <- promise.map(changed_invalid_configuration_fails_closed_test())
  io.println("PASS configuration reload rejects invalid policy")
}
