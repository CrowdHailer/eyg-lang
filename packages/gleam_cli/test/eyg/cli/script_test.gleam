import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/platform
import eyg/cli/internal/source
import eyg/cli/script
import gleam/http
import gleam/javascript/promise
import gleam/option.{None}
import gleam/string
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

pub fn missing_script_field_error_anchors_to_source_test() {
  use return <- promise.map(script.execute(source.Code("{a: 1}"), [], config))
  let assert Error(msg) = return
  let assert True = string.contains(msg, "missing record field: script")
  let assert True = string.contains(msg, "{a: 1}")
}

const eyg_origin = client.Client(
  origin: origin.Origin(http.Https, "eyg.run", None),
)

const config = config.Config(
  client: eyg_origin,
  dirs: platform.PlatformDirs(config_dir: "", cache_dir: "", data_dir: ""),
)
