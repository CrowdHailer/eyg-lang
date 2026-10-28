import gleam/javascript/promise
import gleam/string
import gleeunit
import opencode_plugin.{type Config}
import opencode_plugin/policy
import plinthx/javascript/foreign
import plinthx/javascript/promise as native_promise
import simplifile

pub fn main() {
  gleeunit.main()
}

const fixtures = "test/fixtures"

fn directory() {
  let assert Ok(cwd) = simplifile.current_directory()
  cwd <> "/" <> fixtures
}

fn with_config(then: fn(Config) -> promise.Promise(Nil)) {
  use config <- promise.await(opencode_plugin.load(fixtures <> "/read_only.eyg"))
  let assert Ok(config) = config
  then(config)
}

fn run(code, policy, config) {
  opencode_plugin.run(
    code,
    policy,
    opencode_plugin.config_context(config),
    directory(),
    [],
  )
}

pub fn field_names_test() {
  assert policy.field("ReadFile") == "read_file"
  assert policy.field("CWD") == "cwd"
  assert policy.field("WebFetch") == "web_fetch"
  assert policy.field("Task") == "task"
  assert policy.field("DecodeJSON") == "decode_json"
}

pub fn context_and_pure_code_test() {
  use config <- with_config()
  assert opencode_plugin.config_readme(config) == "hello"
  let policy = opencode_plugin.config_policy(config)
  use report <- promise.map(run("context.readme", policy, config))
  assert opencode_plugin.report_ok(report)
  assert opencode_plugin.report_text(report) == "hello"
}

pub fn passed_effect_is_performed_test() {
  use config <- with_config()
  let policy = opencode_plugin.config_policy(config)
  let code =
    "match perform ReadFile({path: \"notes.md\", offset: 0, limit: 100}) {
      Ok(bytes) -> { !string_from_binary(bytes) }
      Error(reason) -> { Error(reason) }
    }"
  use report <- promise.map(run(code, policy, config))
  assert opencode_plugin.report_text(report) == "Ok(\"# notes\\n\")"
}

pub fn mocked_effect_is_not_performed_test() {
  use config <- with_config()
  let policy = opencode_plugin.config_policy(config)
  let code =
    "perform WriteFile({path: \"out.txt\", contents: !string_to_binary(\"x\")})"
  use report <- promise.map(run(code, policy, config))
  assert opencode_plugin.report_text(report) == "Error(\"read only\")"
  assert simplifile.is_file(fixtures <> "/out.txt") == Ok(False)
}

pub fn effect_without_field_is_unavailable_test() {
  use config <- with_config()
  let policy = opencode_plugin.config_policy(config)
  use report <- promise.map(run("perform Env(\"HOME\")", policy, config))
  assert !opencode_plugin.report_ok(report)
  assert string.contains(
    opencode_plugin.report_text(report),
    "The effect Env is not allowed by your policy, it has no `env` gate.",
  )
}

pub fn standard_out_is_captured_test() {
  use config <- with_config()
  let policy = opencode_plugin.config_policy(config)
  use report <- promise.map(run(
    "let _ = perform StandardOut(\"hi\")
    5",
    policy,
    config,
  ))
  assert opencode_plugin.report_text(report) == "Output:\nhi\nResult:\n5"
}

pub fn subagent_policy_restricts_parent_test() {
  use config <- with_config()
  let parent = opencode_plugin.config_policy(config)
  use child <- promise.await(opencode_plugin.evaluate(
    fixtures <> "/subagent.eyg",
  ))
  let assert Ok(child) = child
  let assert Ok(policy) = opencode_plugin.restrict(parent, child)
  assert opencode_plugin.fields(policy) == ["read_file"]
  let read = fn(path) {
    "match perform ReadFile({path: \"" <> path <> "\", offset: 0, limit: 100}) {
      Ok(_) -> { \"read\" }
      Error(reason) -> { reason }
    }"
  }
  use secret <- promise.await(run(read("secret.txt"), policy, config))
  assert opencode_plugin.report_text(secret) == "only markdown"
  use notes <- promise.await(run(read("notes.md"), policy, config))
  assert opencode_plugin.report_text(notes) == "read"
  use listing <- promise.map(run("perform ReadDirectory(\".\")", policy, config))
  assert !opencode_plugin.report_ok(listing)
}

pub fn agent_policy_replaces_parent_test() {
  use config <- with_config()
  let assert Ok(policy) = opencode_plugin.agent_policy(config, "writer")
  assert opencode_plugin.fields(policy) == ["write_file"]
  assert opencode_plugin.agent_policy(config, "other") == Error(Nil)
  promise.resolve(Nil)
}

pub fn host_effect_test() {
  use config <- with_config()
  let policy = opencode_plugin.config_policy(config)
  let task =
    opencode_plugin.host(
      "Task",
      "{prompt: String}",
      "String",
      foreign.to_dynamic(fn(input, _raw) { promise.resolve(input) }),
    )
  use report <- promise.map(
    opencode_plugin.run(
      "perform Task({prompt: \"go\"})",
      policy,
      opencode_plugin.config_context(config),
      directory(),
      [task],
    ),
  )
  assert opencode_plugin.report_text(report) == "Ok({prompt: \"go\"})"
}

fn configured(code) {
  use config <- promise.map(opencode_plugin.load_source(
    code,
    directory() <> "/config.eyg",
  ))
  let assert Ok(config) = config
  config
}

pub fn file_and_import_gates_receive_normalized_absolute_paths_test() {
  use config <- promise.await(configured(
    "{policy: {read_file: (r) -> {
    match !string_starts_with(r.path, \"/\") {
      True(_) -> { Pass(r) }
      False(_) -> { Mock(Error(\"not absolute\")) }
    }
  }}}",
  ))
  let policy = opencode_plugin.config_policy(config)
  use report <- promise.await(run(
    "import \"./nested/entry.eyg\"",
    policy,
    config,
  ))
  assert opencode_plugin.report_ok(report)
  assert opencode_plugin.report_text(report) == "nested allowed"
  assert opencode_plugin.report_effects(report) == ["ReadFile", "ReadFile"]
  use report <- promise.map(run(
    "perform ReadFile({path: \"notes.md\", offset: 0, limit: 100})",
    policy,
    config,
  ))
  assert opencode_plugin.report_ok(report)
}

pub fn nested_imports_cannot_bypass_a_file_gate_test() {
  use config <- promise.await(configured(
    "{policy: {read_file: (r) -> {
    match !string_ends_with(r.path, \"denied.eyg\") {
      True(_) -> { Mock(Error(\"blocked module\")) }
      False(_) -> { Pass(r) }
    }
  }}}",
  ))
  use report <- promise.map(run(
    "import \"./entry.eyg\"",
    opencode_plugin.config_policy(config),
    config,
  ))
  assert !opencode_plugin.report_ok(report)
  assert string.contains(opencode_plugin.report_text(report), "blocked module")
  assert !string.contains(opencode_plugin.report_text(report), "hidden module")
}

pub fn rewritten_import_paths_anchor_further_imports_to_the_new_file_test() {
  use config <- promise.await(configured(
    "{policy: {read_file: (r) -> {
    match !string_ends_with(r.path, \"alias.eyg\") {
      True(_) -> { Pass({path: \"nested/entry.eyg\", ..r}) }
      False(_) -> { Pass(r) }
    }
  }}}",
  ))
  use report <- promise.map(run(
    "import \"./alias.eyg\"",
    opencode_plugin.config_policy(config),
    config,
  ))
  assert opencode_plugin.report_ok(report)
  assert opencode_plugin.report_text(report) == "nested allowed"
}

pub fn a_parent_gate_sees_the_childs_normalized_rewrite_test() {
  use config <- promise.await(configured(
    "{policy: {read_file: (r) -> {
    match !string_starts_with(r.path, \"/\") {
      True(_) -> { Mock(Error(\"parent saw absolute\")) }
      False(_) -> { Mock(Error(\"relative bypass\")) }
    }
  }}}",
  ))
  use child <- promise.await(opencode_plugin.evaluate_source(
    "{read_file: (r) -> { Pass({path: \"secret.txt\", ..r}) }}",
    directory() <> "/child.eyg",
  ))
  let assert Ok(child) = child
  let assert Ok(policy) =
    opencode_plugin.restrict(opencode_plugin.config_policy(config), child)
  use report <- promise.map(run(
    "perform ReadFile({path: \"notes.md\", offset: 0, limit: 100})",
    policy,
    config,
  ))
  assert opencode_plugin.report_text(report) == "Error(\"parent saw absolute\")"
}

pub fn gates_cannot_perform_effects_or_load_new_references_test() {
  use config <- promise.await(configured(
    "{policy: {read_file: (_) -> { perform Env(\"IGNORED\") }}}",
  ))
  use report <- promise.map(run(
    "perform ReadFile({path: \"notes.md\", offset: 0, limit: 100})",
    opencode_plugin.config_policy(config),
    config,
  ))
  assert !opencode_plugin.report_ok(report)
  assert opencode_plugin.report_effects(report) == ["ReadFile"]
}

pub fn thrown_host_callbacks_resume_with_errors_test() {
  use config <- with_config()
  let hosts = [
    opencode_plugin.host(
      "Task",
      "{}",
      "Any",
      foreign.to_dynamic(fn(_, _) {
        foreign.raise(foreign.error("host failed"))
      }),
    ),
  ]
  use report <- promise.map(opencode_plugin.run(
    "perform Task({})",
    opencode_plugin.config_policy(config),
    opencode_plugin.config_context(config),
    directory(),
    hosts,
  ))
  assert opencode_plugin.report_ok(report)
  assert string.contains(opencode_plugin.report_text(report), "host failed")
}

pub fn rejected_host_promises_resume_with_errors_test() {
  use config <- with_config()
  let assert Ok(constructor) = native_promise.get()
  let hosts = [
    opencode_plugin.host(
      "Task",
      "{}",
      "Any",
      foreign.to_dynamic(fn(_, _) {
        native_promise.reject(constructor, foreign.error("async host failed"))
      }),
    ),
  ]
  use report <- promise.map(opencode_plugin.run(
    "perform Task({})",
    opencode_plugin.config_policy(config),
    opencode_plugin.config_context(config),
    directory(),
    hosts,
  ))
  assert opencode_plugin.report_ok(report)
  assert string.contains(
    opencode_plugin.report_text(report),
    "async host failed",
  )
}

pub fn a_gate_cannot_read_an_import_behind_the_programs_policy_test() {
  use config <- promise.await(configured(
    "{policy: {read_file: (_) -> { import \"./nested/denied.eyg\" }}}",
  ))
  use report <- promise.map(run(
    "perform ReadFile({path: \"notes.md\", offset: 0, limit: 100})",
    opencode_plugin.config_policy(config),
    config,
  ))
  assert !opencode_plugin.report_ok(report)
  assert !string.contains(opencode_plugin.report_text(report), "hidden module")
  assert opencode_plugin.report_effects(report) == ["ReadFile"]
}

pub fn native_file_tool_paths_are_absolute_before_gates_and_callbacks_test() {
  use config <- promise.await(configured(
    "let check = (r) -> {
    match !string_starts_with(r.path, \"/\") {
      True(_) -> { Pass(r) }
      False(_) -> { Mock(Error(\"relative path\")) }
    }
  } {policy: {read: check, write: check, edit: check}}",
  ))
  let callback =
    foreign.to_dynamic(fn(input, _) {
      promise.resolve(foreign.property(input, "path"))
    })
  let hosts = [
    opencode_plugin.host("Read", "{path: String}", "String", callback),
    opencode_plugin.host("Write", "{path: String}", "String", callback),
    opencode_plugin.host("Edit", "{path: String}", "String", callback),
  ]
  use report <- promise.map(opencode_plugin.run(
    "let read = perform Read({path: \"./notes.md\"}) let write = perform Write({path: \"nested/../notes.md\"}) let edit = perform Edit({path: \"notes.md\"}) match !equal(read, write) { True(_) -> { !equal(write, edit) } False(_) -> { False({}) } }",
    opencode_plugin.config_policy(config),
    opencode_plugin.config_context(config),
    directory(),
    hosts,
  ))
  assert opencode_plugin.report_ok(report)
  assert opencode_plugin.report_text(report) == "True({})"
  assert opencode_plugin.report_effects(report) == ["Read", "Write", "Edit"]
}

pub fn native_file_path_fields_are_normalized_together_test() {
  use config <- promise.await(configured("{policy: {read: Pass}}"))
  let hosts = [
    opencode_plugin.host(
      "Read",
      "{file_path: String, path: String}",
      "Any",
      foreign.to_dynamic(fn(input, _) { promise.resolve(input) }),
    ),
  ]
  use report <- promise.map(opencode_plugin.run(
    "perform Read({file_path: \"nested/../notes.md\", path: \"./notes.md\"})",
    opencode_plugin.config_policy(config),
    opencode_plugin.config_context(config),
    directory(),
    hosts,
  ))
  assert opencode_plugin.report_ok(report)
  assert string.contains(
    opencode_plugin.report_text(report),
    "file_path: \"" <> directory() <> "/notes.md\"",
  )
  assert string.contains(
    opencode_plugin.report_text(report),
    "path: \"" <> directory() <> "/notes.md\"",
  )
}
