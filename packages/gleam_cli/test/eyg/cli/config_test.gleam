import eyg/cli/internal/config
import loam/os
import loam/sandbox
import ogre/origin

pub fn default_config_test() {
  let sandbox = sandbox.sandbox() |> sandbox.with_env("HOME", "/home/test")
  let assert #(sandbox.Returned(Ok(config)), _) =
    sandbox.run(config.load(), sandbox)
  assert config.client.origin == origin.https("eyg.run")
  assert config.dirs
    == os.Directories(
      "/home/test/.config",
      "/home/test/.cache",
      "/home/test/.local/share",
    )
}

pub fn configured_origin_is_loaded_from_env_test() {
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_env("HOME", "/home/test")
    |> sandbox.with_env("EYG_ORIGIN", "https://eyg.test")
  let assert #(sandbox.Returned(Ok(config)), _) =
    sandbox.run(config.load(), sandbox)
  assert config.client.origin == origin.https("eyg.test")
}
