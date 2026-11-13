import cloud/beam/execute
import cloud/config
import envoy
import eyg/hub/cache
import filepath
import gleam/bit_array
import gleam/crypto
import gleam/option.{None}
import gleam/result
import ogre/origin

pub fn state() {
  let assert Ok(origin) = origin.from_string_strict("https://eyg.run")
  execute.State(origin:, cache: cache.ready(), root: None, files: None)
}

pub fn directory() {
  let root = envoy.get("TEMP") |> result.unwrap("/tmp")
  filepath.join(
    root,
    "eyg-cloud-" <> bit_array.base16_encode(crypto.strong_random_bytes(12)),
  )
}

pub fn isolated(load: config.Loader) -> config.Loader {
  let directory = directory()
  fn() {
    load()
    |> result.map(fn(config) { config.Workspace(..config, data: directory) })
  }
}
