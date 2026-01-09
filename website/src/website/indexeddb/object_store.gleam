import gleam/dynamic.{type Dynamic}
import gleam/javascript/array.{type Array}
import gleam/javascript/promise.{type Promise}

pub type ObjectStore

pub type DbRequest

@external(javascript, "../../indexeddb_ffi.mjs", "object_store_get_all")
pub fn get_all(
  object_store: ObjectStore,
) -> Promise(Result(Array(Dynamic), String))
