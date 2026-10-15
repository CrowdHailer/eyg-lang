import channel_policy/application
import channel_policy/mock
import channel_policy/policy
import channel_policy/slack
import gleam/option.{None, Some}

pub fn protected_data_is_only_loaded_after_authorization_test() {
  let assert Ok(rules) = mock.rules()
  let assert Ok(ada) = mock.login("ada-code")
  let snapshot =
    slack.refresh(mock.slack_client(True), policy.channels(rules), 1000)
  let allowed =
    application.handle(
      rules,
      Some(ada),
      snapshot,
      "console",
      "/deployments",
      1002,
      fn() { "deployment data" },
    )
  assert allowed
    == application.Response(200, Some("deployment data"), "Allowed")
  let forbidden =
    application.handle(
      rules,
      Some(ada),
      snapshot,
      "console",
      "/finance",
      1002,
      fn() { panic as "Must not load finance data" },
    )
  assert forbidden.status == 403
  assert forbidden.body == None
  let anonymous =
    application.handle(
      rules,
      None,
      snapshot,
      "console",
      "/deployments",
      1002,
      fn() { panic as "Must not load data before login" },
    )
  assert anonymous.status == 401
  let expired =
    application.handle(
      rules,
      Some(ada),
      snapshot,
      "console",
      "/deployments",
      1600,
      fn() { panic as "Must not load data after expiry" },
    )
  assert expired.status == 401
}
