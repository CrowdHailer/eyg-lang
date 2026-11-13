//// Exercise the built extension in an actual official pi session, without a model service.

import envoy
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/string
import javascript/mutable_reference as reference
import pi_extension/native as n
import pi_sdk as sdk
import plinthx/javascript/foreign
import plinthx/javascript/module
import plinthx/node/fs
import simplifile

const config =
  "{
  policy: {read: Pass, edit: Pass, write: (r) -> {
    match !string_ends_with(r.path, \"notes.md\") {
      True(_) -> { Pass(r) }
      False(_) -> { Mock(Error(\"only notes.md can be written\")) }
    }
  }, task: Pass, escalate: Pass},
  context: {readme: \"A test project.\"}
}"

/// Recordable checks using actual SDK sessions and the SDK's faux provider.
pub fn main() {
  use _ <- promise.await(
    real_pi_tools_are_effects_with_policies_and_nested_edit_arguments_test(),
  )
  io.println(
    "PASS actual Pi tools: Read fruit; Write notes; Mock refused fruit overwrite; Bash unavailable; nested Edit changed two to three.",
  )
  use _ <- promise.await(
    only_mode_hides_native_declarations_but_keeps_effects_callable_test(),
  )
  io.println(
    "PASS only-mode: the model sees [eyg], and Read remains callable as an effect.",
  )
  use _ <- promise.await(
    task_subagents_keep_the_restricted_policy_and_only_eyg_test(),
  )
  io.println(
    "PASS Task: child sees [eyg], reads fruit, cannot write notes, and reports model token usage.",
  )
  use _ <- promise.map(
    escalation_requires_ui_approval_before_starting_a_subagent_test(),
  )
  io.println(
    "PASS Escalate: no UI approval, no subagent started. Temporary projects removed.",
  )
  io.println("PASS Pi policy guide")
}

pub type Harness {
  Harness(root: String, session: Dynamic, provider: Dynamic)
}

fn start(entry) {
  let assert Ok(cwd) = simplifile.current_directory()
  use loaded <- promise.await(module.load(cwd <> "/dist/" <> entry <> ".mjs"))
  let assert Ok(loaded) = loaded
  let extension = n.field(loaded, "default")
  let assert Ok(root) = fs.temporary_directory("eyg-roadmap-pi-")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/.pi")
  let assert Ok(_) = simplifile.write(root <> "/.pi/eyg.eyg", config)
  let assert Ok(_) = simplifile.write(root <> "/fruit.txt", "apples\npears\n")
  let provider =
    sdk.faux(
      n.object([
        #(
          "models",
          n.array([
            n.object([
              #("id", n.data("fixture")),
              #("name", n.data("Scripted fixture")),
            ]),
          ]),
        ),
      ]),
    )
  use runtime <- promise.await(
    sdk.model_runtime(
      n.object([
        #("authPath", n.data(root <> "/agent/auth.json")),
        #("modelsPath", foreign.null_value()),
        #("modelsStorePath", n.data(root <> "/agent/models-cache.json")),
        #("allowModelNetwork", n.data(False)),
        #("refreshOnCreate", n.data(False)),
      ]),
    ),
  )
  let _ =
    n.call(runtime, "registerNativeProvider", [n.field(provider, "provider")])
  let settings =
    sdk.settings_manager(
      n.object([
        #("compaction", n.object([#("enabled", n.data(False))])),
        #("retry", n.object([#("enabled", n.data(False))])),
      ]),
    )
  let loader =
    sdk.resource_loader(
      n.object([
        #("cwd", n.data(root)),
        #("agentDir", n.data(root <> "/agent")),
        #("settingsManager", settings),
        #("extensionFactories", n.array([extension])),
        #("noSkills", n.data(True)),
        #("noPromptTemplates", n.data(True)),
        #("noThemes", n.data(True)),
        #("noContextFiles", n.data(True)),
        #("systemPrompt", n.data("Follow the scripted fixture.")),
      ]),
    )
  use _ <- promise.await(n.call(loader, "reload", []) |> foreign.to_promise)
  use created <- promise.await(
    sdk.session(
      n.object([
        #("cwd", n.data(root)),
        #("agentDir", n.data(root <> "/agent")),
        #("modelRuntime", runtime),
        #("model", n.call(provider, "getModel", [])),
        #("thinkingLevel", n.data("off")),
        #("resourceLoader", loader),
        #("sessionManager", sdk.session_manager()),
        #("settingsManager", settings),
      ]),
    ),
  )
  let session = n.field(created, "session")
  use _ <- promise.map(
    n.call(session, "bindExtensions", [n.object([])]) |> foreign.to_promise,
  )
  Harness(root, session, provider)
}

fn with_session(check) {
  with_adapter("index", check)
}

fn with_adapter(entry, check) {
  let config_env = envoy.get("PI_EYG_CONFIG")
  let only_env = envoy.get("PI_EYG_ONLY")
  envoy.unset("PI_EYG_CONFIG")
  envoy.set("PI_EYG_ONLY", "1")
  use harness <- promise.await(start(entry))
  let checked = check(harness) |> promise.map(Ok) |> promise.rescue(Error)
  use checked <- promise.map(checked)
  case checked {
    Error(_) ->
      io.println(string.inspect(
        n.list(n.field(harness.session, "messages"))
        |> list.map(fn(message) {
          #(
            n.string(message, "role"),
            text(message),
            n.string(message, "errorMessage"),
          )
        }),
      ))
    Ok(_) -> Nil
  }
  let _ = n.call(harness.session, "dispose", [])
  let assert Ok(_) = simplifile.delete_all([harness.root])
  restore("PI_EYG_CONFIG", config_env)
  restore("PI_EYG_ONLY", only_env)
  case checked {
    Ok(_) -> Nil
    Error(reason) -> foreign.raise(reason)
  }
  Nil
}

fn restore(name, value) {
  case value {
    Ok(value) -> envoy.set(name, value)
    Error(_) -> envoy.unset(name)
  }
}

fn call(code) {
  sdk.assistant(
    n.array([sdk.tool_call("eyg", n.object([#("code", n.data(code))]))]),
    n.object([#("stopReason", n.data("toolUse"))]),
  )
}

fn say(text) {
  sdk.assistant(n.data(text), n.object([]))
}

fn prompt(harness: Harness, steps) {
  let _ = n.call(harness.provider, "setResponses", [n.array(steps)])
  n.call(harness.session, "prompt", [n.data("Go")]) |> foreign.to_promise
}

fn results(harness: Harness) {
  n.list(n.field(harness.session, "messages"))
  |> list.filter(fn(message) {
    n.string(message, "role") == "toolResult"
    && n.string(message, "toolName") == "eyg"
  })
}

fn text(message) {
  n.joined_text(n.field(message, "content"))
}

pub fn real_pi_tools_are_effects_with_policies_and_nested_edit_arguments_test() {
  use harness <- with_session()
  use _ <- promise.map(
    prompt(harness, [
      call("perform Read({path: \"fruit.txt\"})"),
      call("perform Write({path: \"notes.md\", content: \"two fruit\"})"),
      call("perform Write({path: \"fruit.txt\", content: \"gone\"})"),
      call("perform Bash({command: \"unused\"})"),
      call(
        "perform Edit({path: \"notes.md\", edits: [{old_text: \"two\", new_text: \"three\"}]})",
      ),
      say("done"),
    ]),
  )
  let assert [read, write, denied, bash, edit] = results(harness)
  assert string.contains(text(read), "apples")
  assert string.starts_with(text(write), "Ok(")
  assert text(denied) == "Error(\"only notes.md can be written\")"
  assert string.contains(text(bash), "not allowed by your policy")
  assert !n.bool(n.field(edit, "isError")) as text(edit)
  assert simplifile.read(harness.root <> "/notes.md") == Ok("three fruit")
  assert simplifile.read(harness.root <> "/fruit.txt") == Ok("apples\npears\n")
}

pub fn only_mode_hides_native_declarations_but_keeps_effects_callable_test() {
  use harness <- with_session()
  let declared = reference.new([])
  let inspect =
    n.data(fn(context, _options, _state, _model) {
      reference.set(
        declared,
        sdk.current_tools(context) |> n.list |> list.map(n.string(_, "name")),
      )
      call("perform Read({path: \"fruit.txt\"})")
    })
  use _ <- promise.map(prompt(harness, [inspect, say("done")]))
  assert reference.get(declared) == ["eyg"]
  let assert [read] = results(harness)
  assert string.contains(text(read), "pears")
}

pub fn task_subagents_keep_the_restricted_policy_and_only_eyg_test() {
  use harness <- with_session()
  let declared = reference.new([])
  let inspect =
    n.data(fn(context, _options, _state, _model) {
      reference.set(
        declared,
        sdk.current_tools(context) |> n.list |> list.map(n.string(_, "name")),
      )
      call("perform Read({path: \"fruit.txt\"})")
    })
  use _ <- promise.map(
    prompt(harness, [
      call(
        "perform Task({agent: \"reader\", prompt: \"read fruit.txt\", policy: {read: Pass}})",
      ),
      inspect,
      call("perform Write({path: \"notes.md\", content: \"child\"})"),
      say("The fruit are apples and pears"),
      say("done"),
    ]),
  )
  assert reference.get(declared) == ["eyg"]
  let assert [task] = results(harness)
  assert text(task) == "Ok(\"The fruit are apples and pears\")"
  assert simplifile.is_file(harness.root <> "/notes.md") == Ok(False)
  assert !foreign.is_undefined(n.field(task, "usage"))
  let usage = n.field(task, "usage")
  let assert Ok(input) = decode.run(n.field(usage, "input"), decode.float)
  let assert Ok(output) = decode.run(n.field(usage, "output"), decode.float)
  let assert Ok(total) = decode.run(n.field(usage, "totalTokens"), decode.float)
  assert input >. 0.0
  assert output >. 0.0
  assert total >=. input +. output
}

pub fn escalation_requires_ui_approval_before_starting_a_subagent_test() {
  use harness <- with_session()
  use _ <- promise.map(
    prompt(harness, [
      call(
        "perform Escalate({agent: \"writer\", prompt: \"unused\", policy: {write: Pass}})",
      ),
      say("done"),
    ]),
  )
  let assert [task] = results(harness)
  assert string.contains(text(task), "did not approve")
  assert simplifile.is_file(harness.root <> "/notes.md") == Ok(False)
}

pub fn invalid_changed_config_cannot_reuse_a_previously_allowed_policy_test() {
  use harness <- with_session()
  let changed =
    n.data(fn(_context, _options, _state, _model) {
      let assert Ok(_) = simplifile.write(harness.root <> "/.pi/eyg.eyg", "{")
      call("perform Read({path: \"fruit.txt\"})")
    })
  use _ <- promise.map(
    prompt(harness, [
      call("perform Read({path: \"fruit.txt\"})"),
      changed,
      say("done"),
    ]),
  )
  let assert [first, refused] = results(harness)
  assert string.contains(text(first), "apples")
  assert n.bool(n.field(refused, "isError"))
  assert string.contains(text(refused), "Failed to load EYG configuration")
}

pub fn optional_bash_adapter_blocks_other_commands_in_a_real_pi_session_test() {
  use harness <- with_adapter("bash_only")
  let bash = fn(command) {
    sdk.assistant(
      n.array([sdk.tool_call("bash", n.object([#("command", n.data(command))]))]),
      n.object([#("stopReason", n.data("toolUse"))]),
    )
  }
  use _ <- promise.map(
    prompt(harness, [
      bash("echo should-not-run"),
      bash("eyg eval -c '42' && echo should-not-run"),
      bash("eyg eval -c '\"a;b\"'"),
      say("done"),
    ]),
  )
  let results =
    n.list(n.field(harness.session, "messages"))
    |> list.filter(fn(message) { n.string(message, "role") == "toolResult" })
  let assert [first, second, third] = results
  assert string.contains(text(first), "Only the eyg command can be run")
  assert string.contains(text(second), "Only the eyg command can be run")
  assert !n.bool(n.field(third, "isError")) as text(third)
  assert string.contains(text(third), "a;b")
}
