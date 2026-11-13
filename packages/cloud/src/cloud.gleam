//// Run a cloud: the workspaces in `cloud.eyg`, their connections, the web shell and the API.
////
//// - `CLOUD` the cloud configuration file, defaults to `cloud.eyg`, see `cloud/instance`.
//// - `WORKSPACE` without a `cloud.eyg`, run this one workspace, defaults to `workspace.eyg`.
//// - `EYG_ORIGIN` the hub packages are loaded from, defaults to `https://eyg.run`.
//// - `PORT` the port the web server listens on, defaults to 8081.
//// - `CLOUD_ORIGIN` the public origin of the server, defaults to `http://localhost:<PORT>`.

import cloud/api
import cloud/artifacts
import cloud/beam/execute
import cloud/connections/github
import cloud/instance
import cloud/registry
import cloud/server
import cloud/system
import cloud/tracing
import cloud/web/runner
import cloud/workspace
import envoy
import eyg/hub/cache
import filepath
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import ogre/origin
import simplifile

pub fn main() -> Nil {
  system.configure_proxy()
  let assert Ok(hub) =
    envoy.get("EYG_ORIGIN")
    |> result.unwrap("https://eyg.run")
    |> origin.from_string_strict
  let state = execute.State(origin: hub, cache: cache.ready(), root: None)
  let cloud_file = envoy.get("CLOUD") |> result.unwrap("cloud.eyg")
  let #(load, instance) = case simplifile.is_file(cloud_file) {
    Ok(True) -> {
      let load = instance.loader(cloud_file, state)
      case load() {
        Ok(instance) -> #(load, instance)
        Error(reason) -> panic as reason
      }
    }
    _ -> {
      let file = envoy.get("WORKSPACE") |> result.unwrap("workspace.eyg")
      let instance = instance.single("default", file, state)
      #(fn() { Ok(instance.single("default", file, state)) }, instance)
    }
  }
  let data = case envoy.get("CLOUD_DATA") {
    Ok(data) -> data
    Error(Nil) -> filepath.join(filepath.directory_name(cloud_file), ".data")
  }
  let port = envoy.get("PORT") |> result.try(int.parse) |> result.unwrap(8081)
  let origin =
    envoy.get("CLOUD_ORIGIN")
    |> result.unwrap("http://localhost:" <> int.to_string(port))
  let assert Ok(_) = tracing.start_tracer()
  let assert Ok(artifacts) = artifacts.start(origin)
  let entries =
    list.map(instance.workspaces, fn(entry) { #(entry.name, entry.file) })
  let shells = list.map(instance.shells, fn(shell) { shell.0 })
  let registry = case registry.start(entries, shells, state, artifacts, data) {
    Ok(registry) -> registry
    Error(reason) -> panic as reason
  }
  let handles = process.call(registry, 5000, registry.Workspaces)
  list.each(handles, fn(handle) {
    process.send(
      handle.workspace,
      workspace.SetApi(api.perform(registry, state, _)),
    )
    io.println("Workspace " <> handle.name <> " loaded from " <> handle.file)
  })
  // A delivery goes to the first workspace with a connection of that name.
  let webhook = fn(delivery: github.Delivery) {
    list.fold_until(
      handles,
      Error("no connection named " <> delivery.connection),
      fn(_, handle) {
        case
          process.call(handle.workspace, 5000, workspace.Webhook(delivery, _))
        {
          Error("no connection named " <> _) as error -> list.Continue(error)
          result -> list.Stop(result)
        }
      },
    )
  }
  let web = runner.Context(registry:, instance: load, state:)
  let assert Ok(_) =
    server.start(port, server.Context(artifacts, webhook, Some(web)))
  io.println("Serving at " <> origin)
  process.sleep_forever()
}
