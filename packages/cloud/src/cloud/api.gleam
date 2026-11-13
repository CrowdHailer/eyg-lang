//// The configuration API of a cloud, the operations of `cloud/operation`.
////
//// The same function serves effects in shells and channels and the HTTP API,
//// each caller gates operations with its own policy first.

import cloud/beam/execute
import cloud/config
import cloud/connection
import cloud/data
import cloud/operation.{type Operation}
import cloud/registry
import cloud/secrets
import cloud/workspace
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// Perform an operation. `state` is used to check new workspace configuration.
pub fn perform(
  registry: Subject(registry.Message),
  state: execute.State,
  operation: Operation,
) -> Result(data.Value, String) {
  case operation {
    operation.ListWorkspaces ->
      process.call(registry, 5000, registry.Workspaces)
      |> list.map(fn(h) {
        data.record([
          #("name", data.string(h.name)),
          #("file", data.string(h.file)),
        ])
      })
      |> data.list
      |> Ok
    operation.WorkspaceSource(name) -> {
      use handle <- result.try(registry.workspace(registry, name))
      simplifile.read(handle.file)
      |> result.map(data.string)
      |> result.map_error(simplifile.describe_error)
    }
    operation.SetWorkspaceSource(name, source) -> {
      use handle <- result.try(registry.workspace(registry, name))
      let directory = secrets.data_directory(handle.file)
      use candidate <- result.try(
        config.load_source(handle.file, source, state, secrets.get(directory, _)),
      )
      // Check every currently connected channel against its plugin's native input
      // before replacing the source. New channels are checked when first admitted.
      use _ <- result.try(
        process.call(handle.workspace, 5000, workspace.ListChannels)
        |> list.try_map(fn(info) { config.channel(candidate, info) }),
      )
      simplifile.write(handle.file, source)
      |> result.map_error(simplifile.describe_error)
      |> result.replace(data.record([]))
    }
    operation.ListChannels(name) -> {
      use handle <- result.map(registry.workspace(registry, name))
      process.call(handle.workspace, 5000, workspace.ListChannels)
      |> list.map(fn(info) {
        let config.ChannelInfo(platform:, id:, name:, ..) = info
        data.record([
          #("platform", data.string(platform)),
          #("id", data.string(id)),
          #("name", data.string(name)),
        ])
      })
      |> data.list
    }
    operation.ListConnections(name) -> {
      use handle <- result.map(registry.workspace(registry, name))
      process.call(handle.workspace, 5000, workspace.GetConnections)
      |> list.map(connection.to_value)
      |> data.list
    }
    operation.WorkspaceTriggers(name, channel) -> {
      use handle <- result.try(registry.workspace(registry, name))
      use triggers <- result.map(
        process.call(handle.workspace, 5000, workspace.ChannelTriggers(
          channel,
          _,
        )),
      )
      list.map(triggers, fn(t) {
        data.record([
          #("name", data.string(t.name)),
          #("active", data.bool(t.active)),
        ])
      })
      |> data.list
    }
    operation.ListSecrets(name) -> {
      use handle <- result.try(registry.workspace(registry, name))
      use secrets <- result.map(
        secrets.read(secrets.data_directory(handle.file)),
      )
      dict.keys(secrets) |> list.sort(string.compare) |> data.strings
    }
    operation.SetSecret(name, key, value) -> {
      use handle <- result.try(registry.workspace(registry, name))
      secrets.set(secrets.data_directory(handle.file), key, value)
      |> result.replace(data.record([]))
    }
    operation.DeleteSecret(name, key) -> {
      use handle <- result.try(registry.workspace(registry, name))
      secrets.delete(secrets.data_directory(handle.file), key)
      |> result.replace(data.record([]))
    }
    operation.ListUsers ->
      process.call(registry, 5000, registry.Users)
      |> list.map(fn(u) {
        data.record([
          #("name", data.string(u.name)),
          #("admin", data.bool(u.admin)),
          #("shell", data.string(u.shell)),
        ])
      })
      |> data.list
      |> Ok
    operation.ListShells ->
      process.call(registry, 5000, registry.Shells) |> data.strings |> Ok
    operation.SetUserShell(user, shell) ->
      process.call(registry, 5000, registry.SetUserShell(user, shell, _))
      |> result.replace(data.record([]))
  }
}
