import eyg/interpreter/state
import eyg/interpreter/value as v
import filepath
import gleam/dict
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Resolve filesystem paths in an effect.
/// A base of `None` permits only absolute paths `Some(base)` also permits relative paths.
/// Empty paths, NUL bytes and traversal above root are rejected.
pub fn resolve_input(
  base: Option(String),
  label: String,
  input: state.Value(meta),
) -> Result(state.Value(meta), Nil) {
  case label, input {
    "ReadFile", v.Record(fields)
    | "WriteFile", v.Record(fields)
    | "AppendFile", v.Record(fields)
    ->
      case dict.get(fields, "path") {
        Ok(v.String(path)) -> {
          use path <- result.map(resolve_path(base, path))
          v.Record(dict.insert(fields, "path", v.String(path)))
        }
        _ -> Ok(input)
      }
    "DeleteFile", v.String(path)
    | "MakeDirectory", v.String(path)
    | "ReadDirectory", v.String(path)
    -> result.map(resolve_path(base, path), v.String)
    _, _ -> Ok(input)
  }
}

/// Resolve a path against an optional base.
/// Without a base only absolute paths are accepted.
/// Empty paths, NUL bytes and traversal above root are rejected.
pub fn resolve_path(base: Option(String), path: String) -> Result(String, Nil) {
  case path == "" || string.contains(path, "\u{0}") {
    True -> Error(Nil)
    False ->
      case filepath.is_absolute(path), base {
        True, _ -> filepath.expand(path)
        False, Some(base) -> filepath.expand(filepath.join(base, path))
        False, None -> Error(Nil)
      }
  }
}
