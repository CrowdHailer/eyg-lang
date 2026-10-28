import eyg/cli/internal/client
import eyg/cli/internal/terminal
import eyg/hub/cache
import gleam/bit_array
import gleam/crypto
import gleam/option
import gleam/result
import loam/execute
import loam/os
import loam/system
import ogre/origin

pub type Config {
  Config(client: client.Client, dirs: os.Directories, styled: Bool)
}

/// A separate response store for each complete hub origin, including its scheme.
pub fn hub_store(config: Config) {
  let url = origin.to_string(config.client.origin)
  let identity =
    crypto.hash(crypto.Sha256, bit_array.from_string(url))
    |> bit_array.base16_encode
  config.dirs.cache_dir <> "/eyg/hub/" <> identity
}

pub fn state(config: Config) {
  execute.State(
    config.client.origin,
    cache.empty(),
    option.Some(hub_store(config)),
  )
}

pub fn load() -> system.Effect(Result(Config, Nil)) {
  use configured_origin <- system.then(system.env("EYG_ORIGIN"))
  let origin =
    configured_origin
    |> option.to_result(Nil)
    |> result.try(origin.from_string)
    |> result.unwrap(origin.https("eyg.run"))
  use dirs <- system.then(os.directories())
  use dirs <- system.try(dirs)
  let client = client.Client(origin:)
  // TODO move interactive check to system
  system.Done(Ok(Config(client:, dirs:, styled: terminal.styled())))
}
