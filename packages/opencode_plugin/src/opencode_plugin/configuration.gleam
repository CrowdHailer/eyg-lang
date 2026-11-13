//// Share configuration snapshots and their session-policy routers within a host.

import envoy
import filepath
import gleam/dict
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import javascript/mutable_reference as reference
import opencode_plugin as core
import opencode_plugin/native as n
import opencode_plugin/router
import simplifile

pub type Loaded {
  Loaded(key: String, config: core.Config, router: router.Router)
}

/// Cache by exact file content. Replacing configuration drops its session policies.
pub fn loader(default: String) {
  let snapshots = reference.new(dict.new())
  fn(directory) {
    let override = envoy.get("OPENCODE_EYG_CONFIG") |> result.unwrap("")
    let home = envoy.get("HOME") |> result.unwrap("")
    let project = filepath.join(directory, ".opencode/eyg.eyg")
    let global = filepath.join(home, ".config/opencode/eyg.eyg")
    let file = case override {
      "" ->
        list.find([project, global], fn(path) {
          simplifile.is_file(path) == Ok(True)
        })
        |> result.map(Some)
        |> result.unwrap(None)
      path -> Some(path)
    }
    let #(path, code) = case file {
      Some(path) ->
        case simplifile.read(path) {
          Ok(code) -> #(path, code)
          Error(_) -> n.fail("Failed to read EYG configuration " <> path)
        }
      None -> #(
        filepath.join(directory, "eyg"),
        string.replace(
          default,
          "\"PROJECT\"",
          json.to_string(json.string(directory)),
        ),
      )
    }
    let key = path <> "\n" <> code
    case dict.get(reference.get(snapshots), directory) {
      Ok(Loaded(known, ..) as loaded) if known == key -> promise.resolve(loaded)
      _ -> {
        use loaded <- promise.map(core.load_source(code, path))
        case loaded {
          Error(reason) ->
            n.fail(
              "Failed to load EYG configuration " <> path <> "\n" <> reason,
            )
          Ok(config) -> {
            let loaded = Loaded(key, config, router.new(config))
            let _ =
              reference.set(
                snapshots,
                dict.insert(reference.get(snapshots), directory, loaded),
              )
            loaded
          }
        }
      }
    }
  }
}
