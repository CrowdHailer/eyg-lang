/// Real policy evaluations used by the video renderer. External identities,
/// membership and PR reviews use the same explicit mock adapters as the demo.
import channel_policy/application
import channel_policy/engine
import channel_policy/github
import channel_policy/identity
import channel_policy/mock
import channel_policy/policy
import channel_policy/quota
import channel_policy/slack
import gleam/list
import gleam/option.{Some}
import gleam/result

pub type Capture {
  Capture(
    slack_user: String,
    deployments_status: Int,
    finance_status: Int,
    unreviewed: String,
    wrong_reviewer: String,
    approved: String,
    revoked: String,
    stale_review: String,
    reapproved: String,
    inference_below_limit: Bool,
    inference_at_limit: Bool,
    page_proof: engine.ProofTree,
    approved_proofs: List(engine.ProofTree),
    reapproved_proofs: List(engine.ProofTree),
    inference_proof: engine.ProofTree,
  )
}

/// `head` and `next_head` are actual commits created in an isolated demo repo.
/// The source is the EYG policy file shown in the video's editor.
pub fn capture(head: String, next_head: String, source: String) -> Capture {
  let assert Ok(engine) = engine.compile(source, 100_000)
  let assert Ok(fixture) = mock.rules()
  let rules = policy.Policy(..fixture, engine: engine)
  let assert Ok(ada) = mock.login("ada-code")
  let assert Ok(account) = identity.account(ada, 1002)
  let assert Ok(links) = mock.links()
  let snapshot =
    slack.refresh(mock.slack_client(True), policy.channels(rules), 1000)
  let deployments =
    application.handle(
      rules,
      Some(ada),
      snapshot,
      "console",
      "/deployments",
      1002,
      fn() { "Deployment settings" },
    )
  let finance =
    application.handle(
      rules,
      Some(ada),
      snapshot,
      "console",
      "/finance",
      1002,
      fn() { panic as "Ada must not load finance data" },
    )
  assert deployments.status == 200
  assert finance.status == 403
  let assert policy.Allowed([page_proof]) =
    policy.page(rules, ada, snapshot, "console", "/deployments", 1002)

  let pr = github.PullRequest(..mock.pull_request(), head: head, reviews: [])
  let evaluate = fn(pr, members) {
    github.evaluate(
      rules,
      links,
      members,
      pr,
      github.SubmitterAndReviewer,
      1002,
    )
  }
  let unreviewed = evaluate(pr, snapshot)
  let assert [_] = unreviewed.failures
  let wrong =
    github.PullRequest(..pr, reviews: [
      github.Review("103", head, github.Approved, 1001),
    ])
  let wrong_reviewer = evaluate(wrong, snapshot)
  let assert [_] = wrong_reviewer.failures
  let reviewed =
    github.PullRequest(..pr, reviews: [
      github.Review("102", head, github.Approved, 1001),
    ])
  let approved = evaluate(reviewed, snapshot)
  assert approved.failures == []
  let updated = github.PullRequest(..reviewed, head: next_head)
  let stale = evaluate(updated, snapshot)
  let assert [_] = stale.failures
  let latest =
    github.PullRequest(..updated, reviews: [
      github.Review("102", next_head, github.Approved, 1002),
    ])
  let reapproved = evaluate(latest, snapshot)
  assert reapproved.failures == []
  let revoked =
    evaluate(
      latest,
      slack.refresh(mock.slack_client(False), policy.channels(rules), 1002),
    )
  let assert [_] = revoked.failures
  let assert Ok(quota_engine) = engine.load("policies/llm_quota.eyg", 100_000)
  let usage = quota.Usage(account, "/v1/inference", "2026-10", 49, 1000)
  let limit = quota.Limit(account, "/v1/inference", "2026-10", 50)
  let below =
    quota.authorize_with_proofs(
      quota_engine,
      ada,
      usage,
      limit,
      "/v1/inference",
      "2026-10",
      1002,
      60,
    )
  let at_limit =
    quota.authorize(
      quota_engine,
      ada,
      quota.Usage(..usage, calls: 50),
      limit,
      "/v1/inference",
      "2026-10",
      1002,
      60,
    )
  let assert Ok([quota_permission]) = below
  let assert Error(_) = at_limit
  Capture(
    account.user,
    deployments.status,
    finance.status,
    github.describe(unreviewed),
    github.describe(wrong_reviewer),
    github.describe(approved),
    github.describe(revoked),
    github.describe(stale),
    github.describe(reapproved),
    result.is_ok(below),
    at_limit == Ok(Nil),
    page_proof.tree,
    proof_trees(approved),
    proof_trees(reapproved),
    quota_permission.tree,
  )
}

fn proof_trees(report: github.Report) {
  list.flat_map(report.evidence, fn(evidence) {
    list.map(evidence.proofs, fn(proof) { proof.tree })
  })
}
