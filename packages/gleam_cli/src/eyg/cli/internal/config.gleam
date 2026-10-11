import eyg/cli/internal/client
import eyg/cli/internal/terminal
import gleam/option
import gleam/result
import loam/os
import loam/system
import ogre/origin

pub type Config {
  Config(client: client.Client, dirs: os.Directories, styled: Bool)
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
