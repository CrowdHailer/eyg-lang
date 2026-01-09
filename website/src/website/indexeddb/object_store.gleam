import gleam/dynamic.{type Dynamic}
import gleam/javascript/array.{type Array}
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

pub type ObjectStore

pub type DbRequest

@external(javascript, "../../indexeddb_ffi.mjs", "object_store_get_all")
pub fn get_all(
  object_store: ObjectStore,
) -> Promise(Result(Array(Dynamic), String))

@external(javascript, "../../indexeddb_ffi.mjs", "object_store_put")
fn do_put(
  object_store: ObjectStore,
  item: t,
  key: Json,
) -> Promise(Result(String, String))

pub fn put(
  object_store: ObjectStore,
  item: t,
  key: Option(String),
) -> Promise(Result(String, String)) {
  let key = case key {
    Some(key) -> json.string(key)
    None -> json.null()
  }
  do_put(object_store, item, key)
}
