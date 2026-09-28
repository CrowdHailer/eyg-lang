import eyg/cli/helpers
import eyg/cli/internal/source
import eyg/cli/script
import gleam/javascript/promise
import gleam/string

pub fn print_error_in_import_test() {
  use return <- promise.map(script.execute(
    source.Code(
      "{script: (args) -> { !list_fold(args, 0, (_,i) -> {!int_add(i, 1)}) }}",
    ),
    ["a", "b"],
    helpers.config,
  ))
  let assert Ok(2) = return
}

pub fn missing_script_field_error_anchors_to_source_test() {
  use return <- promise.map(script.execute(
    source.Code("{a: 1}"),
    [],
    helpers.config,
  ))
  let assert Error(msg) = return
  let assert True = string.contains(msg, "missing record field: script")
  let assert True = string.contains(msg, "{a: 1}")
}
