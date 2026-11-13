//// Operations of the cloud's configuration API.
////
//// Every operation is an effect, gated by the shell policy of whoever performs it:
//// a person in the web shell, a program in a channel whose shell allows it, or the HTTP API.
//// See `cloud/api` for their implementation and `guides/cloud/api.md`.

import cloud/data
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/state
import gleam/list
import gleam/result

pub type Operation {
  ListWorkspaces
  WorkspaceSource(workspace: String)
  SetWorkspaceSource(workspace: String, source: String)
  ListChannels(workspace: String)
  ListConnections(workspace: String)
  WorkspaceTriggers(workspace: String, channel: String)
  ListSecrets(workspace: String)
  SetSecret(workspace: String, name: String, value: String)
  DeleteSecret(workspace: String, name: String)
  ListUsers
  ListShells
  SetUserShell(user: String, shell: String)
  /// The most recent spans, newest first, see `cloud/tracing`.
  RecentTraces(limit: Int)
}

/// An operation with its effect name, the policy field gating it and its types.
pub type Spec {
  Spec(
    label: String,
    field: String,
    lift: binding.Mono,
    lower: binding.Mono,
    decode: fn(data.Value) -> Result(Operation, state.Reason(#(Int, Int))),
  )
}

fn unit(operation) {
  fn(value) { cast.as_unit(value, operation) }
}

fn string(f) {
  cast.map(cast.as_string, f)
}

fn fields2(a, b, f) {
  fn(value) {
    use x <- result.try(cast.field(a, cast.as_string, value))
    use y <- result.map(cast.field(b, cast.as_string, value))
    f(x, y)
  }
}

pub fn specs() -> List(Spec) {
  let ok = t.result(t.unit, t.String)
  let strings = t.result(t.List(t.String), t.String)
  [
    Spec(
      "Workspaces",
      "workspaces",
      t.unit,
      t.List(t.record([#("name", t.String), #("file", t.String)])),
      unit(ListWorkspaces),
    ),
    Spec(
      "WorkspaceSource",
      "workspace_source",
      t.String,
      t.result(t.String, t.String),
      string(WorkspaceSource),
    ),
    Spec(
      "SetWorkspaceSource",
      "set_workspace_source",
      t.record([#("workspace", t.String), #("source", t.String)]),
      ok,
      fields2("workspace", "source", SetWorkspaceSource),
    ),
    Spec(
      "Channels",
      "channels",
      t.String,
      t.result(
        t.List(
          t.record([
            #("platform", t.String),
            #("id", t.String),
            #("name", t.String),
          ]),
        ),
        t.String,
      ),
      string(ListChannels),
    ),
    Spec(
      "Connections",
      "connections",
      t.String,
      t.result(
        t.List(
          t.record([
            #("name", t.String),
            #("kind", t.String),
            #("channel", t.option(t.String)),
          ]),
        ),
        t.String,
      ),
      string(ListConnections),
    ),
    Spec(
      "WorkspaceTriggers",
      "workspace_triggers",
      t.record([#("workspace", t.String), #("channel", t.String)]),
      t.result(
        t.List(t.record([#("name", t.String), #("active", t.boolean)])),
        t.String,
      ),
      fields2("workspace", "channel", WorkspaceTriggers),
    ),
    Spec("Secrets", "secrets", t.String, strings, string(ListSecrets)),
    Spec(
      "SetSecret",
      "set_secret",
      t.record([
        #("workspace", t.String),
        #("name", t.String),
        #("value", t.String),
      ]),
      ok,
      fn(value) {
        use workspace <- result.try(cast.field(
          "workspace",
          cast.as_string,
          value,
        ))
        use name <- result.try(cast.field("name", cast.as_string, value))
        use secret <- result.map(cast.field("value", cast.as_string, value))
        SetSecret(workspace, name, secret)
      },
    ),
    Spec(
      "DeleteSecret",
      "delete_secret",
      t.record([#("workspace", t.String), #("name", t.String)]),
      ok,
      fields2("workspace", "name", DeleteSecret),
    ),
    Spec(
      "Users",
      "users",
      t.unit,
      t.List(
        t.record([
          #("name", t.String),
          #("admin", t.boolean),
          #("shell", t.String),
        ]),
      ),
      unit(ListUsers),
    ),
    Spec("Shells", "shells", t.unit, t.List(t.String), unit(ListShells)),
    Spec(
      "Traces",
      "traces",
      t.Integer,
      t.List(
        t.record([
          #("trace", t.String),
          #("span", t.String),
          #("parent", t.option(t.String)),
          #("name", t.String),
          #("start", t.String),
          #("microseconds", t.Integer),
          #("error", t.option(t.String)),
          #(
            "attributes",
            t.List(t.record([#("key", t.String), #("value", t.String)])),
          ),
        ]),
      ),
      cast.map(cast.as_integer, RecentTraces),
    ),
    Spec(
      "SetUserShell",
      "set_user_shell",
      t.record([#("user", t.String), #("shell", t.String)]),
      ok,
      fields2("user", "shell", SetUserShell),
    ),
  ]
}

/// The effect name of an operation.
pub fn label(operation: Operation) -> String {
  case operation {
    ListWorkspaces -> "Workspaces"
    WorkspaceSource(..) -> "WorkspaceSource"
    SetWorkspaceSource(..) -> "SetWorkspaceSource"
    ListChannels(..) -> "Channels"
    ListConnections(..) -> "Connections"
    WorkspaceTriggers(..) -> "WorkspaceTriggers"
    ListSecrets(..) -> "Secrets"
    SetSecret(..) -> "SetSecret"
    DeleteSecret(..) -> "DeleteSecret"
    ListUsers -> "Users"
    ListShells -> "Shells"
    SetUserShell(..) -> "SetUserShell"
    RecentTraces(..) -> "Traces"
  }
}

pub fn spec(label: String) -> Result(Spec, Nil) {
  list.find(specs(), fn(spec) { spec.label == label })
}
