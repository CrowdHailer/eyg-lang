/// Deterministic fixtures. None of these adapters authenticate real tokens or
/// contact Slack/GitHub. Production adapters implement the same typed boundary.
import channel_policy/engine
import channel_policy/github
import channel_policy/identity
import channel_policy/policy
import channel_policy/slack
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result

pub fn oidc() -> identity.Oidc {
  identity.Oidc(fn(code, nonce, _now) {
    case code {
      "ada-code" ->
        Ok(identity.Claims(identity.Account("T_ACME", "U_ADA"), nonce, 2000))
      "bea-code" ->
        Ok(identity.Claims(identity.Account("T_ACME", "U_BEA"), nonce, 2000))
      "cal-code" ->
        Ok(identity.Claims(identity.Account("T_ACME", "U_CAL"), nonce, 2000))
      _ -> Error("Mock OIDC: unknown authorization code")
    }
  })
}

pub fn login(code: String) -> Result(identity.Session, String) {
  use logins <- result.try(identity.begin(
    identity.new_logins(),
    identity.Attempt("demo-state", "demo-browser", "demo-nonce", "T_ACME", 1100),
  ))
  identity.finish(logins, oidc(), "demo-state", "demo-browser", code, 1000, 600).1
}

pub fn github_user(token: String) -> Result(String, String) {
  case token {
    "ada-token" -> Ok("101")
    "bea-token" -> Ok("102")
    "cal-token" -> Ok("103")
    _ -> Error("Mock GitHub: invalid token")
  }
}

pub fn links() -> Result(identity.Links, String) {
  list.try_fold(
    [
      #("ada-code", "ada-token"),
      #("bea-code", "bea-token"),
      #("cal-code", "cal-token"),
    ],
    identity.new_links(),
    fn(links, fixture) {
      use session <- result.try(login(fixture.0))
      identity.link_github(links, session, fixture.1, github_user, 1000)
    },
  )
}

pub fn platform() -> slack.Channel {
  slack.Channel("T_ACME", "C_PLATFORM")
}

pub fn finance() -> slack.Channel {
  slack.Channel("T_ACME", "C_FINANCE")
}

/// Two pages exercise the real pagination loop. Bea can be removed to simulate
/// a membership-change webhook followed by an authoritative refresh.
pub fn slack_client(bea_is_member: Bool) -> slack.Client {
  slack.Client(fn(channel, cursor) {
    case channel, cursor {
      slack.Channel("T_ACME", "C_PLATFORM"), None ->
        Ok(slack.MemberPage(["U_ADA"], Some("page-2")))
      slack.Channel("T_ACME", "C_PLATFORM"), Some("page-2") -> {
        let members = case bea_is_member {
          True -> ["U_BEA"]
          False -> []
        }
        Ok(slack.MemberPage(members, None))
      }
      slack.Channel("T_ACME", "C_FINANCE"), None ->
        Ok(slack.MemberPage(["U_CAL"], None))
      _, _ -> Error("Mock Slack: inaccessible channel or invalid cursor")
    }
  })
}

pub fn rules() -> Result(policy.Policy, String) {
  use engine <- result.try(engine.load(
    "../../eyg_packages/authorization/rbac.eyg",
    100_000,
  ))
  Ok(policy.Policy(
    engine,
    [
      policy.Grant(
        "deployment-page",
        policy.View,
        policy.Exact(policy.Page("console", "/deployments")),
        platform(),
      ),
      policy.Grant(
        "finance-page",
        policy.View,
        policy.Exact(policy.Page("console", "/finance")),
        finance(),
      ),
      policy.Grant(
        "infra-submitter",
        policy.Change,
        policy.Directory("acme/app", "infra"),
        platform(),
      ),
      policy.Grant(
        "infra-reviewer",
        policy.Approve,
        policy.Directory("acme/app", "infra"),
        platform(),
      ),
      policy.Grant(
        "finance-submitter",
        policy.Change,
        policy.Directory("acme/app", "finance"),
        finance(),
      ),
      policy.Grant(
        "finance-reviewer",
        policy.Approve,
        policy.Directory("acme/app", "finance"),
        finance(),
      ),
    ],
    60,
  ))
}

pub fn pull_request() -> github.PullRequest {
  github.PullRequest(
    "acme/app",
    42,
    "head-v1",
    "101",
    1,
    [github.Modified("infra/main.tf")],
    [github.Review("102", "head-v1", github.Approved, 1001)],
  )
}

pub fn github_client(pr: github.PullRequest) -> github.Client {
  github.Client(
    fn(repo, number) {
      case repo == pr.repo && number == pr.number {
        True -> Ok(pr)
        False -> Error("Mock GitHub: PR not found")
      }
    },
    fn(check) {
      let status = case check.status {
        github.Pending -> "PENDING"
        github.Success -> "SUCCESS"
        github.FailureStatus -> "FAILURE"
      }
      io.println("  " <> status <> " " <> check.name <> " @ " <> check.head)
      io.println("  " <> check.summary)
      Ok(Nil)
    },
  )
}
