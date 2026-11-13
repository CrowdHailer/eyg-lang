import channel_policy/engine
import channel_policy/github
import channel_policy/mock
import channel_policy/policy
import channel_policy/slack
import gleam/io
import gleam/list

pub fn main() {
  let assert Ok(rules) = mock.rules()
  let assert Ok(ada) = mock.login("ada-code")
  let assert Ok(links) = mock.links()
  let snapshot =
    slack.refresh(mock.slack_client(True), policy.channels(rules), 1000)

  io.println("1. Ada signs in with Slack and links GitHub account 101.")
  io.println(
    "2. Fetch channel members (including page two), then run EYG rbac.authorize:",
  )
  show_page(
    "/deployments",
    policy.page(rules, ada, snapshot, "console", "/deployments", 1002),
  )
  show_page(
    "/finance",
    policy.page(rules, ada, snapshot, "console", "/finance", 1002),
  )

  io.println("3. PR #42: Ada changes infra/main.tf; Bea approves head-v1.")
  let pr = mock.pull_request()
  let assert Ok(_) =
    github.run(
      mock.github_client(pr),
      mock.slack_client(True),
      rules,
      links,
      pr.repo,
      pr.number,
      github.SubmitterAndReviewer,
      1002,
    )

  io.println("4. Bea leaves #platform. Refresh and reevaluate the same PR:")
  let assert Ok(_) =
    github.run(
      mock.github_client(pr),
      mock.slack_client(False),
      rules,
      links,
      pr.repo,
      pr.number,
      github.SubmitterAndReviewer,
      1003,
    )

  io.println("5. A new commit invalidates the old approval:")
  let updated = github.PullRequest(..pr, head: "head-v2")
  let assert Ok(_) =
    github.run(
      mock.github_client(updated),
      mock.slack_client(True),
      rules,
      links,
      pr.repo,
      pr.number,
      github.SubmitterAndReviewer,
      1004,
    )

  io.println("6. Stale membership snapshots deny page access:")
  show_page(
    "/deployments",
    policy.page(rules, ada, snapshot, "console", "/deployments", 1060),
  )
}

fn show_page(route: String, decision: policy.Decision) {
  case decision {
    policy.Denied(reason) -> io.println("  DENY " <> route <> ": " <> reason)
    policy.Allowed(proofs) -> {
      io.println("  ALLOW " <> route)
      list.each(proofs, fn(proof) {
        io.println(
          "    "
          <> proof.policy_id
          <> " via "
          <> proof.channel.workspace
          <> "/"
          <> proof.channel.id,
        )
        io.println(engine.describe(proof.tree))
      })
    }
  }
}
