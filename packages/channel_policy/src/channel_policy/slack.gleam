/// Paginated Slack membership ingestion with atomic snapshot replacement.
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type Channel {
  Channel(workspace: String, id: String)
}

pub type MemberPage {
  MemberPage(users: List(String), next: Option(String))
}

pub type Client {
  Client(members: fn(Channel, Option(String)) -> Result(MemberPage, String))
}

pub type Membership {
  Membership(channel: Channel, user: String)
}

pub opaque type Snapshot {
  Snapshot(channels: List(Channel), members: List(Membership), observed_at: Int)
}

pub fn refresh(
  client: Client,
  channels: List(Channel),
  now: Int,
) -> Result(Snapshot, String) {
  let channels = list.unique(channels)
  use members <- result.try(
    list.try_map(channels, fn(channel) {
      use users <- result.try(fetch(client, channel, None, [], 1000))
      Ok(list.map(list.unique(users), fn(user) { Membership(channel, user) }))
    }),
  )
  Ok(Snapshot(channels, list.flatten(members), now))
}

fn fetch(
  client: Client,
  channel: Channel,
  cursor: Option(String),
  visited: List(String),
  remaining: Int,
) -> Result(List(String), String) {
  case remaining <= 0 {
    True -> Error("Membership pagination limit exceeded")
    False -> {
      use page <- result.try(client.members(channel, cursor))
      case page.next {
        None | Some("") -> Ok(page.users)
        Some(next) -> {
          case list.contains(visited, next) {
            True -> Error("Repeated membership cursor")
            False -> {
              use rest <- result.try(fetch(
                client,
                channel,
                Some(next),
                [next, ..visited],
                remaining - 1,
              ))
              Ok(list.append(page.users, rest))
            }
          }
        }
      }
    }
  }
}

pub fn memberships(
  snapshot: Snapshot,
  required: List(Channel),
  now: Int,
  max_age: Int,
) -> Result(List(Membership), String) {
  case
    max_age <= 0
    || now < snapshot.observed_at
    || now - snapshot.observed_at >= max_age
  {
    True -> Error("Membership snapshot is stale or has an invalid timestamp")
    False -> {
      case
        list.all(required, fn(channel) {
          list.contains(snapshot.channels, channel)
        })
      {
        True -> Ok(snapshot.members)
        False -> Error("Membership snapshot does not cover required channels")
      }
    }
  }
}
