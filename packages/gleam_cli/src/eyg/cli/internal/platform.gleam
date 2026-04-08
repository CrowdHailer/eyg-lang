//// Notes on OS detection:
//// 
//// - Windows is detected via the OS env var, which Windows sets to Windows_NT by default.
//// - macOS is detected via APPLE_PUBSUB_SOCKET_RENDER, which macOS sets in every login session — it's one of the most reliable macOS-only env vars that doesn't require shell expansion.
//// - Linux is the fallback, since HOME being present and neither of the above matching is a safe heuristic.
//// 
//// Each platform has it's own convention for storing app data.
//// 
//// - Windows → %APPDATA% for config, %LOCALAPPDATA% for cache/data
//// - macOS → ~/Library/Application Support and ~/Library/Caches
//// - Linux → XDG vars with ~/.config, ~/.cache, ~/.local/share as fallbacks

import envoy
import gleam/result
import gleam/string

pub type PlatformDirs {
  PlatformDirs(config_dir: String, cache_dir: String, data_dir: String)
}

pub type OsFamily {
  Windows
  Mac
  Linux
}

fn detect_os() -> OsFamily {
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

fn windows_dirs() -> Result(PlatformDirs, Nil) {
  use appdata <- result.try(envoy.get("APPDATA"))
  use local_appdata <- result.try(
    envoy.get("LOCALAPPDATA") |> result.or(Ok(appdata)),
  )
  Ok(PlatformDirs(
    config_dir: appdata,
    cache_dir: local_appdata <> "\\cache",
    data_dir: local_appdata,
  ))
}

fn mac_dirs() -> Result(PlatformDirs, Nil) {
  use home <- result.try(envoy.get("HOME"))
  Ok(PlatformDirs(
    config_dir: home <> "/Library/Application Support",
    cache_dir: home <> "/Library/Caches",
    data_dir: home <> "/Library/Application Support",
  ))
}

fn linux_dirs() -> Result(PlatformDirs, Nil) {
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
  Ok(PlatformDirs(config_dir: config, cache_dir: cache, data_dir: data))
}

pub fn platform_dirs() -> Result(PlatformDirs, Nil) {
  case detect_os() {
    Windows -> windows_dirs()
    Mac -> mac_dirs()
    Linux -> linux_dirs()
  }
}
