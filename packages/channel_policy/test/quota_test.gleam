import channel_policy/engine
import channel_policy/identity
import channel_policy/mock
import channel_policy/quota
import gleam/list

fn example() {
  let assert Ok(evaluator) = engine.load("policies/llm_quota.eyg", 100_000)
  let assert Ok(session) = mock.login("ada-code")
  let account = identity.Account("T_ACME", "U_ADA")
  let usage = quota.Usage(account, "/v1/inference", "2026-10", 49, 1000)
  let limit = quota.Limit(account, "/v1/inference", "2026-10", 50)
  #(evaluator, session, usage, limit)
}

pub fn allows_only_strictly_below_limit_test() {
  let #(evaluator, session, usage, limit) = example()
  let decide = fn(used) {
    quota.authorize(
      evaluator,
      session,
      quota.Usage(..usage, calls: used),
      limit,
      "/v1/inference",
      "2026-10",
      1002,
      60,
    )
  }
  assert decide(0) == Ok(Nil)
  assert decide(49) == Ok(Nil)
  let assert Error(_) = decide(50)
  let assert Error(_) = decide(51)
  let assert Error(_) = decide(-1)
}

pub fn zero_limit_disables_inference_test() {
  let #(evaluator, session, usage, limit) = example()
  let assert Error(_) =
    quota.authorize(
      evaluator,
      session,
      quota.Usage(..usage, calls: 0),
      quota.Limit(..limit, calls: 0),
      "/v1/inference",
      "2026-10",
      1002,
      60,
    )
}

pub fn allowed_inference_explains_the_actual_usage_comparison_test() {
  let #(evaluator, session, usage, limit) = example()
  let assert Ok([permission]) =
    quota.authorize_with_proofs(
      evaluator,
      session,
      usage,
      limit,
      "/v1/inference",
      "2026-10",
      1002,
      60,
    )
  let assert [quota_fact, usage_fact, action, nonnegative, below] =
    permission.tree.children
  assert quota_fact.title == "Quota"
  assert usage_fact.title == "Usage"
  assert list.key_find(usage_fact.fields, "used") == Ok("49")
  assert list.key_find(quota_fact.fields, "limit") == Ok("50")
  assert action.source == "!equal(action, \"infer\")"
  assert nonnegative.source == "nonnegative(used)"
  assert below.source == "!equal(!int_compare(used, limit), Lt({}))"
  assert list.key_find(below.fields, "used") == Ok("49")
  assert list.key_find(below.fields, "limit") == Ok("50")
}

pub fn usage_and_quota_must_match_user_workspace_endpoint_and_window_test() {
  let #(evaluator, session, usage, limit) = example()
  let check_limit = fn(limit) {
    quota.authorize(
      evaluator,
      session,
      usage,
      limit,
      "/v1/inference",
      "2026-10",
      1002,
      60,
    )
  }
  let assert Error(_) =
    check_limit(
      quota.Limit(..limit, account: identity.Account("T_OTHER", "U_ADA")),
    )
  let assert Error(_) =
    check_limit(
      quota.Limit(..limit, account: identity.Account("T_ACME", "U_BEA")),
    )
  let assert Error(_) = check_limit(quota.Limit(..limit, endpoint: "/v1/other"))
  let assert Error(_) = check_limit(quota.Limit(..limit, window: "2026-09"))
  let assert Error(_) =
    quota.authorize(
      evaluator,
      session,
      quota.Usage(..usage, window: "2026-09"),
      limit,
      "/v1/inference",
      "2026-10",
      1002,
      60,
    )
  let assert Error(_) =
    quota.authorize(
      evaluator,
      session,
      usage,
      limit,
      "/v1/other",
      "2026-10",
      1002,
      60,
    )
}

pub fn expired_session_and_stale_usage_deny_inference_test() {
  let #(evaluator, session, usage, limit) = example()
  let assert Error("Usage snapshot is stale or invalid") =
    quota.authorize(
      evaluator,
      session,
      usage,
      limit,
      "/v1/inference",
      "2026-10",
      1060,
      60,
    )
  let assert Error("Usage snapshot is stale or invalid") =
    quota.authorize(
      evaluator,
      session,
      usage,
      limit,
      "/v1/inference",
      "2026-10",
      999,
      60,
    )
  let assert Error("Session expired") =
    quota.authorize(
      evaluator,
      session,
      usage,
      limit,
      "/v1/inference",
      "2026-10",
      1600,
      60,
    )
}
