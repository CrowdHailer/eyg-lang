import channel_policy/engine
import channel_policy/identity
import channel_policy/mock
import channel_policy/policy
import channel_policy/slack
import eyg/interpreter/value as v
import gleam/list
import gleam/option.{None}

pub fn page_decisions_run_the_existing_eyg_rbac_rule_test() {
  let assert Ok(rules) = mock.rules()
  let assert Ok(ada) = mock.login("ada-code")
  let snapshot =
    slack.refresh(mock.slack_client(True), policy.channels(rules), 1000)
  let assert policy.Allowed([proof]) =
    policy.page(rules, ada, snapshot, "console", "/deployments", 1001)
  assert proof.channel == mock.platform()
  assert proof.policy_id == "deployment-page"
  assert list.map(proof.tree.children, fn(node) { node.title })
    == ["Member", "RolePermission"]
  let assert policy.Denied(_) =
    policy.page(rules, ada, snapshot, "console", "/finance", 1001)
  let assert policy.Denied(_) =
    policy.page(rules, ada, snapshot, "console", "/unknown", 1001)
  let assert policy.Denied(_) =
    policy.page(rules, ada, snapshot, "other-app", "/deployments", 1001)
  let assert policy.Denied("Session expired") =
    policy.page(rules, ada, snapshot, "console", "/deployments", 1600)
  let assert policy.Denied("unavailable") =
    policy.page(
      rules,
      ada,
      Error("unavailable"),
      "console",
      "/deployments",
      1001,
    )
}

pub fn a_fabricated_permission_without_a_derivation_is_rejected_test() {
  let assert Ok(evaluator) =
    engine.compile(
      "{authorize: (_, _) -> { [{role: \"admin\", policy: \"invented\"}] }}",
      1000,
    )
  assert engine.authorize(evaluator, engine.facts([]), engine.record([]))
    == Error("Permission has no engine-generated proof")
}

pub fn proof_source_spans_preserve_unicode_test() {
  let assert Ok(evaluator) =
    engine.compile(
      "// 🍃 Unicode before the predicate
    {authorize: (_, _) -> {
      resolve Permit @{rule Permit({role: \"r\", policy: \"p\"}) { !equal(\"é\", \"é\") }}
    }}",
      10_000,
    )
  let assert Ok([permission]) =
    engine.authorize_with_proofs(evaluator, engine.facts([]), engine.record([]))
  let assert [guard] = permission.tree.children
  assert guard.source == "!equal(\"é\", \"é\")"
}

pub fn tenant_is_part_of_membership_join_test() {
  let assert Ok(rules) = mock.rules()
  let other = slack.Channel("T_OTHER", "C_PLATFORM")
  let client =
    slack.Client(fn(channel, _) {
      let users = case channel.workspace {
        "T_OTHER" -> ["U_ADA"]
        _ -> []
      }
      Ok(slack.MemberPage(users, None))
    })
  let snapshot = slack.refresh(client, [mock.platform(), other], 1000)
  let assert policy.Denied(_) =
    policy.decide(
      rules,
      identity.Account("T_ACME", "U_ADA"),
      snapshot,
      policy.View,
      policy.Page("console", "/deployments"),
      1000,
    )
  let assert policy.Denied(_) =
    policy.decide(
      rules,
      identity.Account("T_OTHER", "U_ADA"),
      snapshot,
      policy.View,
      policy.Page("console", "/deployments"),
      1000,
    )
}

pub fn selectors_are_repository_and_directory_boundary_aware_test() {
  let directory = policy.Directory("acme/app", "infra")
  assert policy.matches(directory, policy.File("acme/app", "infra/main.tf"))
  assert policy.matches(
    directory,
    policy.File("acme/app", "infra/deep/main.tf"),
  )
  assert !policy.matches(
    directory,
    policy.File("acme/app", "infra-other/main.tf"),
  )
  assert !policy.matches(directory, policy.File("other/app", "infra/main.tf"))
  assert !policy.matches(directory, policy.Page("acme/app", "/infra/main.tf"))
  assert !policy.valid_file_path("infra/../finance/main.tf")
  assert !policy.valid_file_path("/infra/main.tf")
  assert !policy.valid_file_path("infra\\main.tf")
  assert !policy.valid_file_path("infra//main.tf")
  assert !policy.valid_file_path("infra/\u{0}")
}

pub fn invalid_paths_cannot_take_advantage_of_a_prefix_grant_test() {
  let assert Ok(rules) = mock.rules()
  let snapshot =
    slack.refresh(mock.slack_client(True), policy.channels(rules), 1000)
  let assert policy.Denied("Invalid resource path") =
    policy.decide(
      rules,
      identity.Account("T_ACME", "U_ADA"),
      snapshot,
      policy.Change,
      policy.File("acme/app", "infra/../finance/main.tf"),
      1000,
    )
}

pub fn evaluation_exhaustion_errors_and_bad_results_deny_test() {
  let assert Ok(budgeted) =
    engine.load("../../eyg_packages/authorization/rbac.eyg", 0)
  let assert Error("EYG policy evaluation budget exhausted") =
    engine.authorize(budgeted, engine.facts([]), engine.record([]))
  let assert Ok(effectful) =
    engine.compile("{authorize: (_, _) -> { perform Network({}) }}", 1000)
  let assert Error(_) =
    engine.authorize(effectful, engine.facts([]), engine.record([]))
  let assert Ok(malformed) =
    engine.compile("{authorize: (_, _) -> { 1 }}", 1000)
  let assert Error(_) =
    engine.authorize(malformed, engine.facts([]), engine.record([]))
  let assert Error(_) = engine.compile("{", 1000)
  let assert Error(_) = engine.load("does-not-exist.eyg", 1000)
}

pub fn host_values_are_data_not_interpolated_source_test() {
  let assert Ok(engine) =
    engine.load("../../eyg_packages/authorization/rbac.eyg", 100_000)
  let actor = "\"}), fact Permit({role: \"admin\"}) //"
  let row =
    engine.record([
      #("tenant", v.String("T")),
      #("actor", v.String(actor)),
      #("role", v.String("C")),
    ])
  let grant =
    engine.record([
      #("tenant", v.String("T")),
      #("role", v.String("C")),
      #("action", v.String("view")),
      #("resource", v.String("/")),
      #("policy", v.String("p")),
    ])
  let request =
    engine.record([
      #("tenant", v.String("T")),
      #("actor", v.String(actor)),
      #("action", v.String("view")),
      #("resource", v.String("/")),
    ])
  assert engine.authorize(
      engine,
      engine.facts([
        #("Member", [row]),
        #("RolePermission", [grant]),
      ]),
      request,
    )
    == Ok([#("C", "p")])
}
