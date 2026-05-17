import birdie
import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/platform
import eyg/cli/internal/source
import eyg/cli/run
import gleam/http
import gleam/javascript/promise
import gleam/option.{None}
import ogre/origin

pub fn print_error_in_import_test() {
  use return <- promise.map(run.execute(
    source.File("./test/fixtures/bad_function_in_import.eyg"),
    config,
  ))
  let assert Error(reason) = return
  birdie.snap(reason, title: "error in imported function")
}

const eyg_origin = client.Client(
  origin: origin.Origin(http.Https, "eyg.run", None),
)

const config = config.Config(
  client: eyg_origin,
  dirs: platform.PlatformDirs(config_dir: "", cache_dir: "", data_dir: ""),
)
