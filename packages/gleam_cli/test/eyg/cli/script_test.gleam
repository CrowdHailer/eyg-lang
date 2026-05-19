import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/platform
import eyg/cli/internal/source
import eyg/cli/script
import gleam/http
import gleam/javascript/promise
import gleam/option.{None}
import ogre/origin

pub fn print_error_in_import_test() {
  use return <- promise.map(script.execute(
    source.Code(
      "{script: (args) -> { !list_fold(args, 0, (_,i) -> {!int_add(i, 1)}) }}",
    ),
    ["a", "b"],
    config,
  ))
  let assert Ok(2) = return
}

const eyg_origin = client.Client(
  origin: origin.Origin(http.Https, "eyg.run", None),
)

const config = config.Config(
  client: eyg_origin,
  dirs: platform.PlatformDirs(config_dir: "", cache_dir: "", data_dir: ""),
)
