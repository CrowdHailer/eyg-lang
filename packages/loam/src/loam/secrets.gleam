//// Secrets mounted by name, i.e. `/user/agent/github`.
////
//// Each secret is a file in `EYG_SECRETS_DIR`, by default `secrets` in the EYG config directory.
//// A name is a path in that directory, it can not leave it.

import filepath
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import loam/os
import loam/system

pub fn mount(name: String) -> system.Effect(Result(String, String)) {
  case relative(name) {
    Error(Nil) -> system.Done(Error("invalid secret name " <> name))
    Ok(relative) -> {
      use directory <- system.then(directory())
      use directory <- system.try(directory)
      use contents <- system.map(
        system.read_file(filepath.join(directory, relative)),
      )
      case contents {
        Ok(contents) -> Ok(trim_newline(contents))
        Error(_) -> Error("no secret named " <> name)
      }
    }
  }
}

/// The directory secrets are kept in.
pub fn directory() -> system.Effect(Result(String, String)) {
  use configured <- system.then(system.env("EYG_SECRETS_DIR"))
  case configured {
    Some(directory) -> system.Done(Ok(directory))
    None -> {
      use directories <- system.map(os.directories())
      case directories {
        Ok(os.Directories(config_dir:, ..)) ->
          Ok(filepath.join(config_dir, "eyg/secrets"))
        Error(Nil) -> Error("no config directory for secrets")
      }
    }
  }
}

/// The path of a secret within the secrets directory.
pub fn relative(name: String) -> Result(String, Nil) {
  let segments =
    string.split(name, "/")
    |> list.filter(fn(segment) { segment != "" })
  case
    segments == []
    || list.any(segments, fn(segment) {
      segment == "." || segment == ".." || string.contains(segment, "\u{0}")
    })
  {
    True -> Error(Nil)
    False -> Ok(string.join(segments, "/"))
  }
}

fn trim_newline(contents) {
  case string.ends_with(contents, "\r\n"), string.ends_with(contents, "\n") {
    True, _ -> string.drop_end(contents, 2)
    False, True -> string.drop_end(contents, 1)
    False, False -> contents
  }
}
