import channel_policy/identity
import channel_policy/mock

fn pending() {
  let assert Ok(logins) =
    identity.begin(
      identity.new_logins(),
      identity.Attempt("state", "browser", "nonce", "T_ACME", 1100),
    )
  logins
}

pub fn successful_login_is_single_use_test() {
  let #(logins, result) =
    identity.finish(
      pending(),
      mock.oidc(),
      "state",
      "browser",
      "ada-code",
      1000,
      60,
    )
  let assert Ok(session) = result
  assert identity.account(session, 1059)
    == Ok(identity.Account("T_ACME", "U_ADA"))
  let assert Error(_) = identity.account(session, 1060)
  let assert #(_, Error(_)) =
    identity.finish(
      logins,
      mock.oidc(),
      "state",
      "browser",
      "ada-code",
      1000,
      60,
    )
}

pub fn browser_state_and_attempt_expiry_test() {
  let assert #(_, Error(_)) =
    identity.finish(
      pending(),
      mock.oidc(),
      "wrong",
      "browser",
      "ada-code",
      1000,
      60,
    )
  let assert #(_, Error(_)) =
    identity.finish(
      pending(),
      mock.oidc(),
      "state",
      "wrong-browser",
      "ada-code",
      1000,
      60,
    )
  let assert #(_, Error(_)) =
    identity.finish(
      pending(),
      mock.oidc(),
      "state",
      "browser",
      "ada-code",
      1100,
      60,
    )
  let assert #(_, Error(_)) =
    identity.finish(
      pending(),
      mock.oidc(),
      "state",
      "browser",
      "ada-code",
      1000,
      0,
    )
}

pub fn failed_exchange_consumes_attempt_test() {
  let #(logins, result) =
    identity.finish(
      pending(),
      mock.oidc(),
      "state",
      "browser",
      "unknown-code",
      1000,
      60,
    )
  let assert Error(_) = result
  let assert #(_, Error(_)) =
    identity.finish(
      logins,
      mock.oidc(),
      "state",
      "browser",
      "ada-code",
      1000,
      60,
    )
}

pub fn invalid_claims_are_rejected_test() {
  let wrong_workspace =
    identity.Oidc(fn(_, nonce, _) {
      Ok(identity.Claims(identity.Account("T_OTHER", "U_ADA"), nonce, 2000))
    })
  let wrong_nonce =
    identity.Oidc(fn(_, _, _) {
      Ok(identity.Claims(identity.Account("T_ACME", "U_ADA"), "wrong", 2000))
    })
  let expired =
    identity.Oidc(fn(_, nonce, _) {
      Ok(identity.Claims(identity.Account("T_ACME", "U_ADA"), nonce, 1000))
    })
  let assert #(_, Error(_)) =
    identity.finish(
      pending(),
      wrong_workspace,
      "state",
      "browser",
      "code",
      1000,
      60,
    )
  let assert #(_, Error(_)) =
    identity.finish(
      pending(),
      wrong_nonce,
      "state",
      "browser",
      "code",
      1000,
      60,
    )
  let assert #(_, Error(_)) =
    identity.finish(pending(), expired, "state", "browser", "code", 1000, 60)
}

pub fn session_cannot_outlive_claims_test() {
  let assert #(_, Ok(session)) =
    identity.finish(
      pending(),
      mock.oidc(),
      "state",
      "browser",
      "ada-code",
      1000,
      5000,
    )
  let assert Ok(_) = identity.account(session, 1999)
  let assert Error(_) = identity.account(session, 2000)
}

pub fn duplicate_or_empty_state_test() {
  let assert Error(_) =
    identity.begin(
      pending(),
      identity.Attempt("state", "browser", "nonce", "T_ACME", 1100),
    )
  let assert Error(_) =
    identity.begin(
      identity.new_logins(),
      identity.Attempt("", "browser", "nonce", "T_ACME", 1100),
    )
}

pub fn account_linking_requires_both_identities_and_rejects_reassignment_test() {
  let assert Ok(ada) = mock.login("ada-code")
  let assert Ok(bea) = mock.login("bea-code")
  let assert Ok(links) =
    identity.link_github(
      identity.new_links(),
      ada,
      "ada-token",
      mock.github_user,
      1000,
    )
  assert identity.resolve(links, "101") == [identity.Account("T_ACME", "U_ADA")]
  assert identity.resolve(links, "unknown") == []
  let assert Ok(_) =
    identity.link_github(links, ada, "ada-token", mock.github_user, 1000)
  let assert Error(_) =
    identity.link_github(links, bea, "ada-token", mock.github_user, 1000)
  let assert Error(_) =
    identity.link_github(links, ada, "bea-token", mock.github_user, 1000)
  let assert Error(_) =
    identity.link_github(links, ada, "bad-token", mock.github_user, 1000)
  let assert Error(_) =
    identity.link_github(links, ada, "ada-token", mock.github_user, 1600)
}
