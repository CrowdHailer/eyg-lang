import gleam/javascript/promise
import gleam/string
import opencode_plugin as core
import opencode_plugin/policy

fn parent(record) {
  use loaded <- promise.map(core.load_source(
    "{policy: " <> record <> "}",
    "/tmp/eyg-policy-chain.eyg",
  ))
  let assert Ok(loaded) = loaded
  loaded
}

fn child(parent, record) {
  use value <- promise.map(core.evaluate_source(
    record,
    "/tmp/eyg-policy-child.eyg",
  ))
  let assert Ok(value) = value
  let assert Ok(child) = core.restrict(parent, value)
  child
}

pub fn omitting_a_default_effect_gate_cannot_reopen_it_test() {
  use config <- promise.await(parent(
    "{standard_out: (_) -> { Mock({}) }, hash: Pass}",
  ))
  use restricted <- promise.await(child(core.config_policy(config), "{}"))
  assert policy.access(restricted, "Hash") == policy.Unavailable
  assert core.fields(restricted) == []
  use report <- promise.map(
    core.run(
      "perform StandardOut(\"hidden\")",
      restricted,
      core.config_context(config),
      "/tmp",
      [],
    ),
  )
  assert !report.ok
  assert report.output == ""
  assert string.contains(core.report_text(report), "not allowed by your policy")
}

pub fn a_child_can_restrict_an_effect_that_is_open_by_default_test() {
  use config <- promise.await(parent("{}"))
  use restricted <- promise.await(child(
    core.config_policy(config),
    "{standard_out: (_) -> { Mock({}) }}",
  ))
  assert core.fields(restricted) == ["standard_out"]
  use report <- promise.map(
    core.run(
      "perform StandardOut(\"hidden\")",
      restricted,
      core.config_context(config),
      "/tmp",
      [],
    ),
  )
  assert report.ok
  assert report.output == ""
}

pub fn descendants_cannot_restore_a_removed_default_effect_test() {
  use config <- promise.await(parent("{standard_out: Pass}"))
  use restricted <- promise.await(child(core.config_policy(config), "{}"))
  use grandchild <- promise.await(child(restricted, "{standard_out: Pass}"))
  assert policy.access(grandchild, "StandardOut") == policy.Unavailable
  assert core.fields(grandchild) == []
  use report <- promise.map(
    core.run(
      "perform StandardOut(\"hidden\")",
      grandchild,
      core.config_context(config),
      "/tmp",
      [],
    ),
  )
  assert !report.ok
  assert report.output == ""
}
