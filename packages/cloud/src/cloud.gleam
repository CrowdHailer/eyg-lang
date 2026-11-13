//// Run a workspace, it starts the connections its `workspace.eyg` configures.
////
//// - `WORKSPACE` the workspace configuration file, defaults to `workspace.eyg`.
//// - `EYG_ORIGIN` the hub packages are loaded from, defaults to `https://eyg.run`.
//// - `PORT` the port artifacts are served on, defaults to 8081.
//// - `CLOUD_ORIGIN` the public origin of the server, defaults to `http://localhost:<PORT>`.

import cloud/artifacts
import cloud/beam/execute
import cloud/config
import cloud/secrets
import cloud/server
import cloud/system
import cloud/workspace
import envoy
import eyg/hub/cache
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/option.{None}
import gleam/result
import ogre/origin

pub fn main() -> Nil {
  system.configure_proxy()
  let assert Ok(hub) =
    envoy.get("EYG_ORIGIN")
    |> result.unwrap("https://eyg.run")
    |> origin.from_string_strict
  let file = envoy.get("WORKSPACE") |> result.unwrap("workspace.eyg")
  let state = execute.State(origin: hub, cache: cache.ready(), root: None)
  let data = secrets.data_directory(file)
  let load = config.loader(file, state, secrets.get(data, _))
  let port = envoy.get("PORT") |> result.try(int.parse) |> result.unwrap(8081)
  let origin =
    envoy.get("CLOUD_ORIGIN")
    |> result.unwrap("http://localhost:" <> int.to_string(port))
  let assert Ok(artifacts) = artifacts.start(origin)
  let workspace = case workspace.start(load, artifacts) {
    Ok(workspace) -> workspace
    Error(reason) -> panic as reason
  }
  io.println("Workspace loaded from " <> file)
  let webhook = fn(delivery) {
    process.call(workspace, 5000, workspace.Webhook(delivery, _))
  }
  let assert Ok(_) = server.start(port, server.Context(artifacts, webhook))
  io.println("Serving at " <> origin)

  process.sleep_forever()
}
