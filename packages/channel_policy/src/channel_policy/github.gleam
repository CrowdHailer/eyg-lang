import channel_policy/engine
import channel_policy/identity.{type Links}
import channel_policy/policy.{
  type Action, type Decision, type Policy, type Proof,
}
import channel_policy/slack.{type Snapshot}
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub type Change {
  Added(path: String)
  Modified(path: String)
  Deleted(path: String)
  Renamed(previous: String, path: String)
}

pub type ReviewState {
  Approved
  ChangesRequested
  Dismissed
  Commented
}

pub type Review {
  Review(user: String, commit: String, state: ReviewState, submitted_at: Int)
}

pub type PullRequest {
  PullRequest(
    repo: String,
    number: Int,
    head: String,
    author: String,
    changed_file_count: Int,
    files: List(Change),
    reviews: List(Review),
  )
}

pub type Requirements {
  Submitter
  Reviewer
  SubmitterAndReviewer
}

pub type Evidence {
  Evidence(path: String, action: Action, user: String, proofs: List(Proof))
}

pub type Failure {
  Failure(path: String, action: Action, reason: String)
}

pub type Report {
  Report(evidence: List(Evidence), failures: List(Failure))
}

pub type Status {
  Pending
  Success
  FailureStatus
}

pub type Check {
  Check(
    repo: String,
    pull_request: Int,
    head: String,
    name: String,
    status: Status,
    summary: String,
    evaluated_at: Int,
  )
}

pub type Client {
  Client(
    // Adapter returns a complete, coherent snapshot, including all review pages.
    // Return Error rather than silently truncate at an API result limit.
    fetch: fn(String, Int) -> Result(PullRequest, String),
    publish: fn(Check) -> Result(Nil, String),
  )
}

pub fn paths(change: Change) -> List(String) {
  case change {
    Added(path) | Modified(path) | Deleted(path) -> [path]
    Renamed(previous, path) -> list.unique([previous, path])
  }
}

pub fn evaluate(
  rules: Policy,
  links: Links,
  snapshot: Result(Snapshot, String),
  pr: PullRequest,
  requirements: Requirements,
  now: Int,
) -> Report {
  case
    pr.head == ""
    || pr.author == ""
    || pr.repo == ""
    || pr.number <= 0
    || pr.changed_file_count <= 0
    || pr.changed_file_count != list.length(pr.files)
    || list.length(list.unique(pr.files)) != list.length(pr.files)
  {
    True -> Report([], [Failure("*", policy.Change, "Incomplete PR snapshot")])
    False -> {
      let paths = list.flat_map(pr.files, paths) |> list.unique
      let reviewers = eligible_reviewers(pr)
      list.fold(paths, Report([], []), fn(report, path) {
        let report = case requirements {
          Reviewer -> report
          _ -> {
            let decision =
              for_github_user(
                rules,
                links,
                snapshot,
                pr.author,
                policy.Change,
                policy.File(pr.repo, path),
                now,
              )
            append_decision(report, path, policy.Change, pr.author, decision)
          }
        }
        case requirements {
          Submitter -> report
          _ -> {
            let allowed =
              list.filter_map(reviewers, fn(user) {
                case
                  for_github_user(
                    rules,
                    links,
                    snapshot,
                    user,
                    policy.Approve,
                    policy.File(pr.repo, path),
                    now,
                  )
                {
                  policy.Allowed(proofs) ->
                    Ok(Evidence(path, policy.Approve, user, proofs))
                  policy.Denied(_) -> Error(Nil)
                }
              })
            case allowed {
              [] ->
                Report(report.evidence, [
                  Failure(
                    path,
                    policy.Approve,
                    "No eligible channel member approved the current head",
                  ),
                  ..report.failures
                ])
              _ ->
                Report(list.append(report.evidence, allowed), report.failures)
            }
          }
        }
      })
    }
  }
}

fn append_decision(
  report: Report,
  path: String,
  action: Action,
  user: String,
  decision: Decision,
) -> Report {
  case decision {
    policy.Allowed(proofs) ->
      Report(
        [Evidence(path, action, user, proofs), ..report.evidence],
        report.failures,
      )
    policy.Denied(reason) ->
      Report(report.evidence, [Failure(path, action, reason), ..report.failures])
  }
}

fn for_github_user(
  rules: Policy,
  links: Links,
  snapshot: Result(Snapshot, String),
  user: String,
  action: Action,
  resource: policy.Resource,
  now: Int,
) -> Decision {
  let accounts = identity.resolve(links, user)
  let decisions =
    list.map(accounts, fn(account) {
      policy.decide(rules, account, snapshot, action, resource, now)
    })
  let proofs =
    list.flat_map(decisions, fn(decision) {
      case decision {
        policy.Allowed(proofs) -> proofs
        policy.Denied(_) -> []
      }
    })
  case proofs, decisions {
    [], [] -> policy.Denied("GitHub identity has no verified Slack link")
    [], [decision, ..] -> decision
    _, _ -> policy.Allowed(proofs)
  }
}

fn eligible_reviewers(pr: PullRequest) -> List(String) {
  // Latest decisive review wins. A later comment does not erase an approval.
  let ordered =
    pr.reviews
    |> list.filter(fn(review) { review.state != Commented })
    |> list.sort(fn(a, b) { int.compare(b.submitted_at, a.submitted_at) })
  let latest =
    list.fold(ordered, [], fn(latest, review) {
      case
        list.any(latest, fn(previous: Review) { previous.user == review.user })
      {
        True -> latest
        False -> [review, ..latest]
      }
    })
  list.filter_map(latest, fn(review) {
    case
      review.state == Approved
      && review.commit == pr.head
      && review.user != pr.author
      // Slack/GitHub adapters may expose second-resolution timestamps. Do not
      // choose an approval arbitrarily when conflicting reviews share a time.
      && list.all(ordered, fn(other) {
        other.user != review.user
        || other.submitted_at != review.submitted_at
        || { other.state == Approved && other.commit == pr.head }
      })
    {
      True -> Ok(review.user)
      False -> Error(Nil)
    }
  })
}

/// Run on PR/review updates AND membership changes. The host must reevaluate
/// pending PRs on expiry as well; GitHub success statuses do not expire.
pub fn run(
  client: Client,
  slack_client: slack.Client,
  rules: Policy,
  links: Links,
  repo: String,
  number: Int,
  requirements: Requirements,
  now: Int,
) -> Result(Report, String) {
  use pr <- result.try(client.fetch(repo, number))
  use _ <- result.try(case pr.repo == repo && pr.number == number {
    True -> Ok(Nil)
    False -> Error("GitHub adapter returned the wrong PR")
  })
  let pending =
    Check(
      repo,
      number,
      pr.head,
      "channel-policy",
      Pending,
      "Checking current Slack memberships",
      now,
    )
  use _ <- result.try(client.publish(pending))
  let snapshot = slack.refresh(slack_client, policy.channels(rules), now)
  let report = evaluate(rules, links, snapshot, pr, requirements, now)
  let status = case report.failures {
    [] -> Success
    _ -> FailureStatus
  }
  use _ <- result.try(client.publish(
    Check(..pending, status: status, summary: describe_with_proofs(report)),
  ))
  Ok(report)
}

pub fn describe(report: Report) -> String {
  case report.failures {
    [] ->
      "Allowed: "
      <> int.to_string(list.length(report.evidence))
      <> " permission proofs"
    failures ->
      failures
      |> list.map(fn(failure) {
        failure.path
        <> " ["
        <> policy.action_name(failure.action)
        <> "]: "
        <> failure.reason
      })
      |> string.join("\n")
  }
}

pub fn describe_with_proofs(report: Report) -> String {
  let summary = describe(report)
  case report.failures {
    [_, ..] -> summary
    [] -> {
      let trees =
        list.flat_map(report.evidence, fn(evidence) {
          list.map(evidence.proofs, fn(proof) {
            evidence.path
            <> " ["
            <> policy.action_name(evidence.action)
            <> "] GitHub user "
            <> evidence.user
            <> "\n"
            <> engine.describe(proof.tree)
          })
        })
      string.join([summary, ..trees], "\n\n")
    }
  }
}
