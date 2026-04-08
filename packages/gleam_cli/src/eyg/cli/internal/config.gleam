import envoy
import eyg/cli/internal/client
import eyg/cli/internal/platform
import gleam/result.{try}
import ogre/origin

pub type Config {
  Config(client: client.Client, dirs: platform.PlatformDirs)
}

pub fn load() {
  let origin =
    envoy.get("EYG_ORIGIN")
    |> result.try(origin.from_string)
    |> result.unwrap(origin.https("eyg.run"))
  use dirs <- try(platform.platform_dirs())
  let client = client.Client(origin:)
  Ok(Config(client:, dirs:))
}
