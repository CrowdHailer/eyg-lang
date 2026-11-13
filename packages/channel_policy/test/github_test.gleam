import channel_policy/github
import channel_policy/identity
import channel_policy/mock
import channel_policy/policy
import channel_policy/slack
import gleam/list

fn evaluate(
  pr: github.PullRequest,
  mode: github.Requirements,
  bea_is_member: Bool,
) {
  let assert Ok(rules) = mock.rules()
  let assert Ok(links) = mock.links()
  let snapshot =
    slack.refresh(
      mock.slack_client(bea_is_member),
      policy.channels(rules),
      1000,
    )
  github.evaluate(rules, links, snapshot, pr, mode, 1002)
}

pub fn submitter_and_reviewer_both_need_permissions_test() {
  let report = evaluate(mock.pull_request(), github.SubmitterAndReviewer, True)
  assert report.failures == []
  let assert Ok(submitter) =
    list.find(report.evidence, fn(e) { e.action == policy.Change })
  let assert Ok(reviewer) =
    list.find(report.evidence, fn(e) { e.action == policy.Approve })
  assert submitter.user == "101"
  assert reviewer.user == "102"
  let assert [submitter_proof] = submitter.proofs
  let assert [reviewer_proof] = reviewer.proofs
  assert submitter_proof.policy_id == "infra-submitter"
  assert reviewer_proof.policy_id == "infra-reviewer"
  assert reviewer_proof.channel == mock.platform()
  let assert [member, permission] = reviewer_proof.tree.children
  assert list.key_find(member.fields, "actor") == Ok("\"U_BEA\"")
  assert list.key_find(permission.fields, "action") == Ok("\"approve\"")
}

pub fn every_path_must_be_authorized_test() {
  let pr =
    github.PullRequest(..mock.pull_request(), changed_file_count: 2, files: [
      github.Modified("infra/main.tf"),
      github.Modified("finance/report.csv"),
    ])
  let report = evaluate(pr, github.SubmitterAndReviewer, True)
  assert list.length(report.failures) == 2
  assert list.all(report.failures, fn(failure) {
    failure.path == "finance/report.csv"
  })
}

pub fn renamed_old_path_and_deletions_are_checked_test() {
  let pr =
    github.PullRequest(..mock.pull_request(), files: [
      github.Renamed("finance/report.csv", "infra/report.csv"),
    ])
  let report = evaluate(pr, github.Submitter, True)
  let assert [failure] = report.failures
  assert failure.path == "finance/report.csv"
  let deleted =
    github.PullRequest(..pr, files: [github.Deleted("finance/report.csv")])
  let assert [_] = evaluate(deleted, github.Submitter, True).failures
}

pub fn new_unknown_files_and_repositories_default_to_deny_test() {
  let pr =
    github.PullRequest(..mock.pull_request(), files: [
      github.Added("unowned.txt"),
    ])
  let assert [_] = evaluate(pr, github.Submitter, True).failures
  let other_repo = github.PullRequest(..mock.pull_request(), repo: "other/app")
  let assert [_] = evaluate(other_repo, github.Submitter, True).failures
}

pub fn cannot_reuse_approval_after_push_or_membership_removal_test() {
  let pr = mock.pull_request()
  let assert [_] = evaluate(pr, github.SubmitterAndReviewer, False).failures
  let pushed = github.PullRequest(..pr, head: "head-v2")
  let assert [_] = evaluate(pushed, github.SubmitterAndReviewer, True).failures
}

pub fn self_reviews_and_unlinked_reviewers_do_not_count_test() {
  let pr = mock.pull_request()
  let self_reviewed =
    github.PullRequest(..pr, reviews: [
      github.Review(pr.author, pr.head, github.Approved, 1001),
    ])
  let assert [_] = evaluate(self_reviewed, github.Reviewer, True).failures
  let unlinked =
    github.PullRequest(..pr, reviews: [
      github.Review("999", pr.head, github.Approved, 1001),
    ])
  let assert [_] = evaluate(unlinked, github.Reviewer, True).failures
}

pub fn latest_decisive_review_controls_approval_test() {
  let pr = mock.pull_request()
  let rejected =
    github.PullRequest(..pr, reviews: [
      github.Review("102", pr.head, github.ChangesRequested, 1002),
      ..pr.reviews
    ])
  let assert [_] = evaluate(rejected, github.Reviewer, True).failures
  let dismissed =
    github.PullRequest(..pr, reviews: [
      github.Review("102", pr.head, github.Dismissed, 1002),
      ..pr.reviews
    ])
  let assert [_] = evaluate(dismissed, github.Reviewer, True).failures
  let commented =
    github.PullRequest(..pr, reviews: [
      github.Review("102", pr.head, github.Commented, 1002),
      ..pr.reviews
    ])
  assert evaluate(commented, github.Reviewer, True).failures == []
}

pub fn submitter_and_reviewer_modes_are_independent_test() {
  let pr = github.PullRequest(..mock.pull_request(), author: "103")
  assert evaluate(pr, github.Reviewer, True).failures == []
  let assert [_] = evaluate(pr, github.Submitter, True).failures
  let unreviewed = github.PullRequest(..mock.pull_request(), reviews: [])
  assert evaluate(unreviewed, github.Submitter, True).failures == []
  let assert [_] = evaluate(unreviewed, github.Reviewer, True).failures
}

pub fn ambiguous_review_order_fails_closed_test() {
  let pr = mock.pull_request()
  let reviews = [
    github.Review("102", pr.head, github.ChangesRequested, 1001),
    ..pr.reviews
  ]
  let assert [_] =
    evaluate(github.PullRequest(..pr, reviews: reviews), github.Reviewer, True).failures
  let assert [_] =
    evaluate(
      github.PullRequest(..pr, reviews: list.reverse(reviews)),
      github.Reviewer,
      True,
    ).failures
}

pub fn truncated_or_empty_file_snapshots_cannot_pass_test() {
  let truncated =
    github.PullRequest(..mock.pull_request(), changed_file_count: 2)
  let assert [_] = evaluate(truncated, github.Submitter, True).failures
  let empty =
    github.PullRequest(..mock.pull_request(), files: [], changed_file_count: 0)
  let assert [_] = evaluate(empty, github.Submitter, True).failures
}

pub fn missing_identity_and_stale_or_failed_membership_deny_test() {
  let assert Ok(rules) = mock.rules()
  let assert Ok(links) = mock.links()
  let snapshot =
    slack.refresh(mock.slack_client(True), policy.channels(rules), 1000)
  let pr = mock.pull_request()
  let assert [_] =
    github.evaluate(
      rules,
      identity.new_links(),
      snapshot,
      pr,
      github.Submitter,
      1002,
    ).failures
  let assert [_] =
    github.evaluate(rules, links, snapshot, pr, github.Submitter, 1060).failures
  let assert [_] =
    github.evaluate(rules, links, Error("offline"), pr, github.Submitter, 1002).failures
}

pub fn runner_publishes_failure_on_slack_outage_test() {
  let assert Ok(rules) = mock.rules()
  let assert Ok(links) = mock.links()
  let pr = mock.pull_request()
  let client =
    github.Client(fn(_, _) { Ok(pr) }, fn(check) {
      assert check.head == "head-v1"
      assert check.name == "channel-policy"
      assert check.status != github.Success
      Ok(Nil)
    })
  let offline = slack.Client(fn(_, _) { Error("offline") })
  let assert Ok(report) =
    github.run(
      client,
      offline,
      rules,
      links,
      pr.repo,
      pr.number,
      github.SubmitterAndReviewer,
      1002,
    )
  assert list.length(report.failures) == 2
}

pub fn publish_failure_is_not_reported_as_a_success_test() {
  let assert Ok(rules) = mock.rules()
  let assert Ok(links) = mock.links()
  let pr = mock.pull_request()
  let client =
    github.Client(fn(_, _) { Ok(pr) }, fn(check) {
      case check.status {
        github.Pending -> Ok(Nil)
        _ -> Error("GitHub publish failed")
      }
    })
  assert github.run(
      client,
      mock.slack_client(True),
      rules,
      links,
      pr.repo,
      pr.number,
      github.SubmitterAndReviewer,
      1002,
    )
    == Error("GitHub publish failed")
}

pub fn runner_rejects_wrong_pr_from_adapter_test() {
  let assert Ok(rules) = mock.rules()
  let assert Ok(links) = mock.links()
  let client =
    github.Client(fn(_, _) { Ok(mock.pull_request()) }, fn(_) {
      panic as "Should not publish for the wrong PR"
    })
  let assert Error("GitHub adapter returned the wrong PR") =
    github.run(
      client,
      mock.slack_client(True),
      rules,
      links,
      "other/repo",
      42,
      github.Submitter,
      1002,
    )
}
