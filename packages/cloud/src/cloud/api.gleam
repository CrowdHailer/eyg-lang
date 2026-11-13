//// The configuration API of a cloud, the operations of `cloud/operation`.
////
//// The same function serves effects in shells and channels and the HTTP API,
//// each caller gates operations with its own policy first.

import cloud/beam/execute
import cloud/config
import cloud/configuration
import cloud/connection
import cloud/data
import cloud/operation.{type Operation}
import cloud/registry
import cloud/tracing
import cloud/workspace
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import otel/clock
import otel/span

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
      Ok(data.string(
        process.call(handle.settings, 5000, configuration.Get).source,
      ))
    }
    operation.SetWorkspaceSource(name, source) -> {
      use handle <- result.try(registry.workspace(registry, name))
      let snapshot = process.call(handle.settings, 5000, configuration.Get)
      use candidate <- result.try(
        config.load_source(handle.file, source, state, fn(key) {
          dict.get(snapshot.secrets, key)
          |> result.replace_error("no secret named " <> key)
        }),
      )
      // Check every currently connected channel against its plugin's native input
      // before replacing the source. New channels are checked when first admitted.
      use _ <- result.try(
        process.call(handle.workspace, 5000, workspace.ListChannels)
        |> list.try_map(fn(info) { config.channel(candidate, info) }),
      )
      process.call(handle.settings, 5000, configuration.SetSource(source, _))
      Ok(data.record([]))
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
      let snapshot = process.call(handle.settings, 5000, configuration.Get)
      dict.keys(snapshot.secrets)
      |> list.sort(string.compare)
      |> data.strings
      |> Ok
    }
    operation.SetSecret(name, key, value) -> {
      use handle <- result.try(registry.workspace(registry, name))
      process.call(handle.settings, 5000, configuration.SetSecret(key, value, _))
      Ok(data.record([]))
    }
    operation.DeleteSecret(name, key) -> {
      use handle <- result.try(registry.workspace(registry, name))
      process.call(handle.settings, 5000, configuration.DeleteSecret(key, _))
      Ok(data.record([]))
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
    operation.RecentTraces(limit) ->
      tracing.recent(limit)
      |> list.map(fn(span) {
        data.record([
          #("trace", data.string(span.trace_id)),
          #("span", data.string(span.span_id)),
          #("parent", data.option(span.parent_id, data.string)),
          #("name", data.string(span.name)),
          #("start", data.string(clock.encode(span.started))),
          #(
            "microseconds",
            data.int(clock.difference(span.ended, span.started) / 1000),
          ),
          #("error", data.option(span.error, data.string)),
          #(
            "attributes",
            data.list(
              list.map(span.attributes, fn(attribute) {
                data.record([
                  #("key", data.string(attribute.0)),
                  #("value", data.string(attribute_text(attribute.1))),
                ])
              }),
            ),
          ),
        ])
      })
      |> data.list
      |> Ok
    operation.SetUserShell(user, shell) ->
      process.call(registry, 5000, registry.SetUserShell(user, shell, _))
      |> result.replace(data.record([]))
  }
}

fn attribute_text(attribute: span.Attribute) -> String {
  case attribute {
    span.Text(text) -> text
    span.Integer(i) -> int.to_string(i)
    span.Boolean(True) -> "true"
    span.Boolean(False) -> "false"
    span.Real(f) -> float.to_string(f)
    span.Array(items) -> string.join(list.map(items, attribute_text), ", ")
  }
}
