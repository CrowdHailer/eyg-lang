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

import envoy
import gleam/result
import gleam/string

pub type Directories {
  Directories(config_dir: String, cache_dir: String, data_dir: String)
}

pub type Family {
  Windows
  Mac
  Linux
}

pub fn detect() -> Family {
  case envoy.get("OS") {
    Ok("Windows" <> _) -> Windows
    _ ->
      case envoy.get("HOME") {
        Ok(_) ->
          case envoy.get("TMPDIR") {
            Ok(val) ->
              case
                string.contains(val, "var/folders"),
                string.contains(val, "AppData")
              {
                True, _ -> Mac
                _, True -> Windows
                False, False -> Linux
              }
            _ ->
              case envoy.get("APPLE_PUBSUB_SOCKET_RENDER") {
                Ok(_) -> Mac
                _ -> Linux
              }
          }
        _ -> Linux
      }
  }
}

fn windows_directories() -> Result(Directories, Nil) {
  use appdata <- result.try(envoy.get("APPDATA"))
  use local_appdata <- result.try(
    envoy.get("LOCALAPPDATA") |> result.or(Ok(appdata)),
  )
  Ok(Directories(
    config_dir: appdata,
    cache_dir: local_appdata <> "\\cache",
    data_dir: local_appdata,
  ))
}

fn mac_directories() -> Result(Directories, Nil) {
  use home <- result.try(envoy.get("HOME"))
  let config =
    envoy.get("XDG_CONFIG_HOME")
    |> result.unwrap(home <> "/Library/Application Support")
  let cache =
    envoy.get("XDG_CACHE_HOME")
    |> result.unwrap(home <> "/Library/Caches")
  let data =
    envoy.get("XDG_DATA_HOME")
    |> result.unwrap(home <> "/Library/Application Support")
  Ok(Directories(config_dir: config, cache_dir: cache, data_dir: data))
}

fn linux_directories() -> Result(Directories, Nil) {
  use home <- result.try(envoy.get("HOME"))
  let config =
    envoy.get("XDG_CONFIG_HOME")
    |> result.unwrap(home <> "/.config")
  let cache =
    envoy.get("XDG_CACHE_HOME")
    |> result.unwrap(home <> "/.cache")
  let data =
    envoy.get("XDG_DATA_HOME")
    |> result.unwrap(home <> "/.local/share")
  Ok(Directories(config_dir: config, cache_dir: cache, data_dir: data))
}

pub fn directories() -> Result(Directories, Nil) {
  case detect() {
    Windows -> windows_directories()
    Mac -> mac_directories()
    Linux -> linux_directories()
  }
}
