import gleam/javascript/promise
import plinth/browser/window
import website/indexeddb/database.{type Database}

pub type Factory

@external(javascript, "../../indexeddb_ffi.mjs", "window_indexeddb")
pub fn from_window(window: window.Window) -> Result(Factory, Nil)

/// Used only in open
pub type OpenDbRequest

/// Throws TypeError if the value of version is not a number greater than zero.
@external(javascript, "../../indexeddb_ffi.mjs", "factory_open")
pub fn open(
  factory: Factory,
  name: String,
  version: Int,
) -> Result(OpenDbRequest, String)

@external(javascript, "../../indexeddb_ffi.mjs", "open_db_on_success")
pub fn on_success(request: OpenDbRequest, callback: fn(Database) -> Nil) -> Nil

@external(javascript, "../../indexeddb_ffi.mjs", "open_db_on_error")
pub fn on_error(request: OpenDbRequest, callback: fn(String) -> Nil) -> Nil

@external(javascript, "../../indexeddb_ffi.mjs", "open_db_on_upgrade_needed")
pub fn on_upgrade_needed(
  request: OpenDbRequest,
  callback: fn(Database) -> Nil,
) -> Nil

pub fn opendb(factory, name, version, upgrade) {
  promise.new(fn(resolve) {
    case open(factory, name, version) {
      Ok(open_request) -> {
        on_success(open_request, fn(db) { resolve(Ok(db)) })
        on_error(open_request, fn(reason) { resolve(Error(reason)) })
        on_upgrade_needed(open_request, upgrade)
      }
      Error(reason) -> resolve(Error(reason))
    }
  })
}
