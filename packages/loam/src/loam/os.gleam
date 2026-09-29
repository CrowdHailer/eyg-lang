//// This module provides operating-system identification and directory conventions, including those from the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/).
////
//// Notes on OS detection:
//// 
//// - Windows is detected via the OS env var, which Windows sets to Windows_NT by default.
//// - macOS is detected via APPLE_PUBSUB_SOCKET_RENDER, which macOS sets in every login session — it's one of the most reliable macOS-only env vars that doesn't require shell expansion.
//// - Linux is the fallback, since HOME being present and neither of the above matching is a safe heuristic.
//// 
//// Each operating system has its own conventions for storing app data.
//// 
//// - Windows → %APPDATA% for config, %LOCALAPPDATA% for cache/data
//// - macOS → XDG vars with ~/Library paths as fallbacks
//// - Linux → XDG vars with ~/.config, ~/.cache, ~/.local/share as fallbacks

import gleam/option.{None, Some}
import gleam/string
import loam/system

pub type Directories {
  Directories(config_dir: String, cache_dir: String, data_dir: String)
}

pub type Family {
  Windows
  Mac
  Linux
}

pub fn detect() -> system.Effect(Family) {
  use os <- system.then(system.env("OS"))
  case os {
    Some("Windows" <> _) -> system.Done(Windows)
    _ -> {
      use home <- system.then(system.env("HOME"))
      case home {
        Some(_) -> {
          use tmpdir <- system.then(system.env("TMPDIR"))
          case tmpdir {
            Some(val) -> {
              let family = case
                string.contains(val, "var/folders"),
                string.contains(val, "AppData")
              {
                True, _ -> Mac
                _, True -> Windows
                False, False -> Linux
              }
              system.Done(family)
            }
            None -> {
              use socket <- system.map(system.env("APPLE_PUBSUB_SOCKET_RENDER"))
              case socket {
                Some(_) -> Mac
                None -> Linux
              }
            }
          }
        }
        None -> system.Done(Linux)
      }
    }
  }
}

fn windows_directories() -> system.Effect(Result(Directories, Nil)) {
  use appdata <- system.then(system.env("APPDATA"))
  use appdata <- system.try(option.to_result(appdata, Nil))
  use local_appdata <- system.map(system.env("LOCALAPPDATA"))
  let local_appdata = option.unwrap(local_appdata, appdata)
  Ok(Directories(
    config_dir: appdata,
    cache_dir: local_appdata <> "\\cache",
    data_dir: local_appdata,
  ))
}

fn mac_directories() -> system.Effect(Result(Directories, Nil)) {
  use home <- system.then(system.env("HOME"))
  use home <- system.try(option.to_result(home, Nil))
  use config <- system.then(system.env("XDG_CONFIG_HOME"))
  let config = option.unwrap(config, home <> "/Library/Application Support")
  use cache <- system.then(system.env("XDG_CACHE_HOME"))
  let cache = option.unwrap(cache, home <> "/Library/Caches")
  use data <- system.map(system.env("XDG_DATA_HOME"))
  let data = option.unwrap(data, home <> "/Library/Application Support")
  Ok(Directories(config_dir: config, cache_dir: cache, data_dir: data))
}

fn linux_directories() -> system.Effect(Result(Directories, Nil)) {
  use home <- system.then(system.env("HOME"))
  use home <- system.try(option.to_result(home, Nil))
  use config <- system.then(system.env("XDG_CONFIG_HOME"))
  let config = option.unwrap(config, home <> "/.config")
  use cache <- system.then(system.env("XDG_CACHE_HOME"))
  let cache = option.unwrap(cache, home <> "/.cache")
  use data <- system.map(system.env("XDG_DATA_HOME"))
  let data = option.unwrap(data, home <> "/.local/share")
  Ok(Directories(config_dir: config, cache_dir: cache, data_dir: data))
}

pub fn directories() -> system.Effect(Result(Directories, Nil)) {
  use family <- system.then(detect())
  case family {
    Windows -> windows_directories()
    Mac -> mac_directories()
    Linux -> linux_directories()
  }
}
