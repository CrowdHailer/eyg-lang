import channel_policy/engine.{type Engine}
import channel_policy/identity.{type Account, type Session}
import channel_policy/slack.{type Channel, type Snapshot}
import eyg/interpreter/value as v
import gleam/list
import gleam/result
import gleam/string

pub type Action {
  View
  Change
  Approve
}

pub type Resource {
  Page(app: String, route: String)
  File(repo: String, path: String)
}

pub type Selector {
  Exact(Resource)
  Directory(repo: String, path: String)
}

pub type Grant {
  Grant(id: String, action: Action, selector: Selector, channel: Channel)
}

pub type Proof {
  Proof(channel: Channel, policy_id: String, tree: engine.ProofTree)
}

pub type Decision {
  Allowed(proofs: List(Proof))
  Denied(reason: String)
}

pub type Policy {
  Policy(engine: Engine, grants: List(Grant), membership_max_age: Int)
}

pub fn channels(policy: Policy) -> List(Channel) {
  list.map(policy.grants, fn(grant) { grant.channel }) |> list.unique
}

/// Call this from server-side route/API handlers using their canonical route.
pub fn page(
  policy: Policy,
  session: Session,
  snapshot: Result(Snapshot, String),
  app: String,
  route: String,
  now: Int,
) -> Decision {
  case identity.account(session, now) {
    Error(reason) -> Denied(reason)
    Ok(account) ->
      decide(policy, account, snapshot, View, Page(app, route), now)
  }
}

pub fn decide(
  policy: Policy,
  account: Account,
  snapshot: Result(Snapshot, String),
  action: Action,
  resource: Resource,
  now: Int,
) -> Decision {
  let evaluated = {
    use _ <- result.try(case valid_resource(resource) {
      True -> Ok(Nil)
      False -> Error("Invalid resource path")
    })
    let grants =
      list.filter(policy.grants, fn(grant) {
        grant.action == action
        && grant.channel.workspace == account.workspace
        && matches(grant.selector, resource)
      })
    use _ <- result.try(case grants {
      [] -> Error("No matching policy")
      _ -> Ok(Nil)
    })
    use snapshot <- result.try(snapshot)
    use members <- result.try(slack.memberships(
      snapshot,
      list.map(grants, fn(grant) { grant.channel }),
      now,
      policy.membership_max_age,
    ))
    let member_facts =
      list.map(members, fn(member) {
        engine.record([
          #("tenant", v.String(member.channel.workspace)),
          #("actor", v.String(member.user)),
          #("role", v.String(member.channel.id)),
        ])
      })
    let grant_facts =
      list.map(grants, fn(grant) {
        engine.record([
          #("tenant", v.String(grant.channel.workspace)),
          #("role", v.String(grant.channel.id)),
          #("action", v.String(action_name(action))),
          #("resource", resource_value(resource)),
          #("policy", v.String(grant.id)),
        ])
      })
    let db =
      engine.facts([
        #("Member", member_facts),
        #("RolePermission", grant_facts),
      ])
    let request =
      engine.record([
        #("tenant", v.String(account.workspace)),
        #("actor", v.String(account.user)),
        #("action", v.String(action_name(action))),
        #("resource", resource_value(resource)),
      ])
    use rows <- result.try(engine.authorize_with_proofs(
      policy.engine,
      db,
      request,
    ))
    Ok(
      list.map(rows, fn(row) {
        Proof(slack.Channel(account.workspace, row.role), row.policy, row.tree)
      }),
    )
  }
  case evaluated {
    Error(reason) -> Denied(reason)
    Ok([]) -> Denied("No channel membership grants this action")
    Ok(proofs) -> Allowed(proofs)
  }
}

pub fn action_name(action: Action) -> String {
  case action {
    View -> "view"
    Change -> "change"
    Approve -> "approve"
  }
}

fn resource_value(resource: Resource) -> engine.Value {
  let #(kind, scope, path) = case resource {
    Page(app, route) -> #("page", app, route)
    File(repo, path) -> #("file", repo, path)
  }
  engine.record([
    #("kind", v.String(kind)),
    #("scope", v.String(scope)),
    #("path", v.String(path)),
  ])
}

pub fn matches(selector: Selector, resource: Resource) -> Bool {
  case selector, resource {
    Exact(expected), actual -> expected == actual
    Directory(repo, directory), File(actual_repo, path) ->
      repo == actual_repo
      && valid_file_path(directory)
      && string.starts_with(path, directory <> "/")
    _, _ -> False
  }
}

fn valid_resource(resource: Resource) -> Bool {
  case resource {
    File(repo, path) -> repo != "" && valid_file_path(path)
    Page(app, route) ->
      app != ""
      && string.starts_with(route, "/")
      && { route == "/" || valid_file_path(string.drop_start(route, 1)) }
  }
}

/// Reject ambiguous names rather than silently normalize GitHub file paths.
pub fn valid_file_path(path: String) -> Bool {
  path != ""
  && !string.contains(path, "\\")
  && !string.contains(path, "\u{0}")
  && list.all(string.split(path, "/"), fn(segment) {
    segment != "" && segment != "." && segment != ".."
  })
}
