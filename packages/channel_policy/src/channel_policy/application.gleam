/// Server-side enforcement shared by HTML pages and their backing API routes.
import channel_policy/identity.{type Session}
import channel_policy/policy.{type Policy}
import channel_policy/slack.{type Snapshot}
import gleam/option.{type Option, None, Some}

pub type Response(body) {
  Response(status: Int, body: Option(body), reason: String)
}

/// `route` is an application-selected permission resource, not arbitrary user
/// input. For example /api/deployments and /deployments can both map to the
/// permission resource /deployments. Protected data is loaded only on allow.
pub fn handle(
  rules: Policy,
  session: Option(Session),
  snapshot: Result(Snapshot, String),
  app: String,
  route: String,
  now: Int,
  load: fn() -> body,
) -> Response(body) {
  case session {
    None -> Response(401, None, "Sign in with Slack")
    Some(session) -> {
      case identity.account(session, now) {
        Error(reason) -> Response(401, None, reason)
        Ok(_) -> {
          case policy.page(rules, session, snapshot, app, route, now) {
            policy.Denied(reason) -> Response(403, None, reason)
            policy.Allowed(_) -> Response(200, Some(load()), "Allowed")
          }
        }
      }
    }
  }
}
