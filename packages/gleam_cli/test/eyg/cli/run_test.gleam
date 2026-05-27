import birdie
import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/platform
import eyg/cli/internal/source
import eyg/cli/run
import gleam/http
import gleam/javascript/promise
import gleam/option.{None}
import gleam/string
import ogre/origin
import simplifile

pub fn print_error_in_import_test() {
  use return <- promise.map(run.execute(
    source.File("././././test/fixtures/../fixtures/bad_function_in_import.eyg"),
    config,
  ))
  let assert Error(reason) = return
  birdie.snap(reason, title: "error in imported function")
}

pub fn abort_in_nested_helper_test() {
  use return <- promise.map(run.execute(
    source.File("./test/fixtures/abort_main.eyg"),
    config,
  ))
  let assert Error(reason) = return
  birdie.snap(reason, title: "abort in nested helper")
}

pub fn file_effects_are_source_relative_test() {
  use return <- promise.map(run.execute(
    source.File("./test/fixtures/source_relative/main.eyg"),
    config,
  ))
  let assert Ok(0) = return
}

pub fn cwd_effect_allows_inline_code_to_read_invocation_files_test() {
  use return <- promise.map(run.execute(
    source.Code(
      "let cwd = match perform CWD({}) {
  Ok(cwd) -> { cwd }
  Error(_) -> { !never(perform Abort(\"unspecified cwd\")) }
}
let path = !string_append(cwd, \"/test/fixtures/hello.txt\")
match perform ReadFile({path, offset: 0, limit: 100}) {
  Ok(bytes) -> {
    match !equal(bytes, !string_to_binary(\"Hello, World!\")) {
      True(_) -> { 0 }
      False(_) -> { !never(perform Abort(\"wrong contents\")) }
    }
  }
  Error(reason) -> { !never(perform Abort(reason)) }
}",
    ),
    config,
  ))
  let assert Ok(0) = return
}

pub fn inline_relative_file_effect_returns_error_test() {
  use return <- promise.map(run.execute(
    source.Code(
      "match perform ReadFile({path: \"hello.txt\", offset: 0, limit: 100}) {
  Ok(_) -> { !never(perform Abort(\"unexpected read\")) }
  Error(reason) -> {
    match !equal(reason, \"relative path \\\"hello.txt\\\" requires a disk-backed source; use CWD or an absolute path\") {
      True(_) -> { 0 }
      False(_) -> { !never(perform Abort(reason)) }
    }
  }
}",
    ),
    config,
  ))
  let assert Ok(0) = return
}

pub fn inline_relative_import_errors_test() {
  use return <- promise.map(run.execute(
    source.Code("import \"test/fixtures/source_relative/value.eyg\""),
    config,
  ))
  let assert Error(reason) = return
  assert string.contains(
    reason,
    "relative location undefined: test/fixtures/source_relative/value.eyg",
  )
}

pub fn inline_absolute_import_works_test() {
  let assert Ok(cwd) = simplifile.current_directory()
  let path = cwd <> "/test/fixtures/source_relative/value.eyg"
  let code = "let value = import \"" <> path <> "\"
match !equal(value, 5) {
  True(_) -> { 0 }
  False(_) -> { !never(perform Abort(\"wrong value\")) }
}"
  use return <- promise.map(run.execute(source.Code(code), config))
  let assert Ok(0) = return
}

const eyg_origin = client.Client(
  origin: origin.Origin(http.Https, "eyg.run", None),
)

const config = config.Config(
  client: eyg_origin,
  dirs: platform.PlatformDirs(config_dir: "", cache_dir: "", data_dir: ""),
)
