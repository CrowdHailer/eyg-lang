//// Dataclips are named functions in a workspace's configuration that run with their own policy.
////
//// A dataclip is how a channel reads data it has no direct access to.
//// Raw database access, the `SQLite` and `SQLiteQuery` effects, is for trusted channels.
//// A dataclip's author writes and reviews the query once, with a shell that can only reach what it needs,
//// and any channel whose shell has the `dataclip` effect calls it by name with an input.
//// The channel's gate sees the name and input, so a channel can be limited to some dataclips.
////
//// ```eyg
//// dataclips: [{
////   name: "recent_errors",
////   description: "Errors since a unix time, `{since: 1700000000}`",
////   shell: cloud.shell.databases(["errors"]),
////   clip: (input) -> {
////     perform SQLite({database: "errors", sql: "SELECT message FROM errors WHERE at > ?", parameters: [Integer(input.since)]})
////   }
//// }]
//// ```
////
//// A dataclip runs in the process of the program that calls it, with the configuration
//// that process loaded, so no EYG value crosses a process boundary.

import cloud/beam/execute
import cloud/config
import cloud/database
import cloud/tracing
import eyg/ir/tree as ir
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Run the dataclip `name` of a workspace with an input.
/// A dataclip's host only has the workspace's databases, its shell decides which.
pub fn run(
  workspace: config.Workspace,
  name: String,
  input: execute.Value,
  trace: Option(tracing.Context),
) -> Result(execute.Value, String) {
  use dataclip <- result.try(find(workspace, name))
  let host =
    execute.Host(
      ..execute.configuration_host(fn(_) {
        Error("Dataclips cannot read secrets")
      }),
      database: database.path(workspace.data, _),
      trace:,
    )
  let call = #(
    ir.Apply(#(ir.Variable("clip"), #(0, 0)), #(ir.Variable("input"), #(0, 0))),
    #(0, 0),
  )
  let scope = [#("clip", dataclip.clip), #("input", input)]
  let #(execute.Run(result:, ..), _state) =
    execute.run_expression(call, scope, dataclip.shell, host, workspace.state)
  case result {
    Ok(Some(value)) -> Ok(value)
    Ok(None) -> Error("dataclip " <> name <> " returned no value")
    Error(reason) -> Error("dataclip " <> name <> ": " <> reason)
  }
}

fn find(workspace: config.Workspace, name) {
  case list.find(workspace.dataclips, fn(d) { d.name == name }) {
    Ok(dataclip) -> Ok(dataclip)
    Error(Nil) -> {
      let names = list.map(workspace.dataclips, describe)
      Error(
        "no dataclip named "
        <> name
        <> ", the dataclips are: "
        <> string.join(names, "; "),
      )
    }
  }
}

/// A dataclip's name and description.
pub fn describe(dataclip: config.Dataclip) -> String {
  case dataclip.description {
    "" -> dataclip.name
    description -> dataclip.name <> " - " <> description
  }
}
