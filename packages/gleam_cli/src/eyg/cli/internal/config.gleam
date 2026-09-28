import envoy
import eyg/cli/internal/client
import gleam/result.{try}
import loam/os
import ogre/origin

pub type Config {
  Config(client: client.Client, dirs: os.Directories)
}

pub fn load() {
  let origin =
    envoy.get("EYG_ORIGIN")
    |> result.try(origin.from_string)
    |> result.unwrap(origin.https("eyg.run"))
  use dirs <- try(os.directories())
  let client = client.Client(origin:)
  Ok(Config(client:, dirs:))
}
