/// Login orchestration. Cryptographic OIDC verification belongs to the adapter.
import gleam/list
import gleam/result

pub type Account {
  Account(workspace: String, user: String)
}

/// The exchange adapter must validate signature, issuer, audience and nonce
/// before returning these claims. The mock adapter is only for local demos.
pub type Claims {
  Claims(account: Account, nonce: String, expires_at: Int)
}

pub type Oidc {
  Oidc(exchange: fn(String, String, Int) -> Result(Claims, String))
}

pub type Attempt {
  Attempt(
    state: String,
    browser_binding: String,
    nonce: String,
    workspace: String,
    expires_at: Int,
  )
}

pub opaque type Logins {
  Logins(List(Attempt))
}

pub opaque type Session {
  Session(account: Account, expires_at: Int)
}

pub fn new_logins() -> Logins {
  Logins([])
}

/// Supply cryptographically random state, nonce and browser binding in a host.
pub fn begin(logins: Logins, attempt: Attempt) -> Result(Logins, String) {
  let Logins(pending) = logins
  case
    attempt.state == ""
    || attempt.nonce == ""
    || attempt.browser_binding == ""
    || attempt.workspace == ""
    || list.any(pending, fn(p) { p.state == attempt.state })
  {
    True -> Error("Invalid or duplicate login attempt")
    False -> Ok(Logins([attempt, ..pending]))
  }
}

/// Persist the returned Logins even on failure: callbacks are single-use.
pub fn finish(
  logins: Logins,
  provider: Oidc,
  state: String,
  browser_binding: String,
  code: String,
  now: Int,
  session_ttl: Int,
) -> #(Logins, Result(Session, String)) {
  let Logins(pending) = logins
  let remaining = Logins(list.filter(pending, fn(p) { p.state != state }))
  let session = {
    use attempt <- result.try(
      list.find(pending, fn(p) { p.state == state })
      |> result.replace_error("Unknown or consumed login state"),
    )
    case
      attempt.browser_binding != browser_binding
      || now >= attempt.expires_at
      || session_ttl <= 0
    {
      True -> Error("Invalid browser binding or expired login attempt")
      False -> {
        use claims <- result.try(provider.exchange(code, attempt.nonce, now))
        case
          claims.nonce != attempt.nonce
          || claims.account.workspace != attempt.workspace
          || claims.account.user == ""
          || now >= claims.expires_at
        {
          True -> Error("Invalid identity claims")
          False -> {
            let expires_at = case now + session_ttl < claims.expires_at {
              True -> now + session_ttl
              False -> claims.expires_at
            }
            Ok(Session(claims.account, expires_at))
          }
        }
      }
    }
  }
  #(remaining, session)
}

pub fn account(session: Session, now: Int) -> Result(Account, String) {
  case now < session.expires_at {
    True -> Ok(session.account)
    False -> Error("Session expired")
  }
}

pub type Link {
  Link(github_id: String, slack: Account)
}

pub opaque type Links {
  Links(List(Link))
}

pub fn new_links() -> Links {
  Links([])
}

/// The host completes a state-bound GitHub OAuth flow first. The adapter
/// resolves its access token through GitHub's authenticated-user endpoint.
pub fn link_github(
  links: Links,
  session: Session,
  github_token: String,
  authenticated_user: fn(String) -> Result(String, String),
  now: Int,
) -> Result(Links, String) {
  use slack <- result.try(account(session, now))
  use github_id <- result.try(authenticated_user(github_token))
  let Links(existing) = links
  case
    github_id == ""
    || list.any(existing, fn(link) {
      // One GitHub identity per Slack account; one Slack account per workspace
      // for a GitHub identity. The same person can link multiple workspaces.
      link != Link(github_id, slack)
      && {
        link.slack == slack
        || {
          link.github_id == github_id && link.slack.workspace == slack.workspace
        }
      }
    })
  {
    True -> Error("Identity already linked or invalid")
    False -> Ok(Links(list.unique([Link(github_id, slack), ..existing])))
  }
}

pub fn resolve(links: Links, github_id: String) -> List(Account) {
  let Links(links) = links
  list.filter_map(links, fn(link) {
    case link.github_id == github_id {
      True -> Ok(link.slack)
      False -> Error(Nil)
    }
  })
}
