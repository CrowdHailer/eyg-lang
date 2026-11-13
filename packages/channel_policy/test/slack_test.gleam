import channel_policy/mock
import channel_policy/slack
import gleam/list
import gleam/option.{None, Some}

pub fn fetches_every_page_and_replaces_removed_members_test() {
  let assert Ok(before) =
    slack.refresh(mock.slack_client(True), [mock.platform()], 1000)
  let assert Ok(members) =
    slack.memberships(before, [mock.platform()], 1000, 60)
  assert list.contains(members, slack.Membership(mock.platform(), "U_BEA"))
  let assert Ok(after) =
    slack.refresh(mock.slack_client(False), [mock.platform()], 1001)
  let assert Ok(members) = slack.memberships(after, [mock.platform()], 1001, 60)
  assert members == [slack.Membership(mock.platform(), "U_ADA")]
}

pub fn empty_page_with_cursor_is_not_end_of_pagination_test() {
  let client =
    slack.Client(fn(_, cursor) {
      case cursor {
        None -> Ok(slack.MemberPage([], Some("more")))
        Some(_) -> Ok(slack.MemberPage(["U_ADA", "U_ADA"], Some("")))
      }
    })
  let assert Ok(snapshot) = slack.refresh(client, [mock.platform()], 1000)
  assert slack.memberships(snapshot, [mock.platform()], 1000, 60)
    == Ok([slack.Membership(mock.platform(), "U_ADA")])
}

pub fn partial_and_cyclic_pagination_fail_closed_test() {
  let failed =
    slack.Client(fn(_, cursor) {
      case cursor {
        None -> Ok(slack.MemberPage(["U_ADA"], Some("more")))
        Some(_) -> Error("ratelimited")
      }
    })
  let cyclic =
    slack.Client(fn(_, _) { Ok(slack.MemberPage(["U_ADA"], Some("again"))) })
  let assert Error("ratelimited") =
    slack.refresh(failed, [mock.platform()], 1000)
  let assert Error("Repeated membership cursor") =
    slack.refresh(cyclic, [mock.platform()], 1000)
}

pub fn rejects_stale_future_and_incomplete_snapshots_test() {
  let assert Ok(snapshot) =
    slack.refresh(mock.slack_client(True), [mock.platform()], 1000)
  let assert Ok(_) = slack.memberships(snapshot, [mock.platform()], 1059, 60)
  let assert Error(_) = slack.memberships(snapshot, [mock.platform()], 1060, 60)
  let assert Error(_) = slack.memberships(snapshot, [mock.platform()], 999, 60)
  let assert Error(_) = slack.memberships(snapshot, [mock.finance()], 1000, 60)
  let assert Error(_) = slack.memberships(snapshot, [mock.platform()], 1000, 0)
}
