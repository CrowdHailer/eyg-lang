//// Read source inputs and resolve paths using the local computer.

import filepath
import gleam/option.{None, Some}
import gleam/result
import loam/system
import touch_grass/file_system
import touch_grass/source

pub fn read_input(
  input: source.Input,
) -> system.Effect(Result(String, String)) {
  case input {
    source.File(path:) -> system.read_file(path)
    source.Code(code:) -> system.Done(Ok(code))
    source.Stdin -> system.stdin()
  }
}

/// Resolve a source-relative path, requesting CWD only for interactive origins.
pub fn resolve_filepath(
  origin: source.Origin,
  path: String,
) -> system.Effect(Result(String, String)) {
  use base <- system.map(case filepath.is_absolute(path), origin {
    True, _ -> system.Done(Ok(None))
    False, source.Host(path) ->
      system.Done(Ok(Some(filepath.directory_name(path))))
    False, source.Inline -> {
      use cwd <- system.map(system.cwd())
      result.map(cwd, Some)
    }
    False, source.Content(_) | False, source.Release(..) ->
      system.Done(Ok(None))
  })
  use base <- result.try(base)
  file_system.resolve_path(base, path)
  |> result.replace_error("invalid relative path outside filesystem")
}
