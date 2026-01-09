import gleam/javascript/array.{type Array}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import website/indexeddb/object_store.{type ObjectStore}
import website/indexeddb/transaction.{type Transaction}

pub type Database

@external(javascript, "../../indexeddb_ffi.mjs", "database_name")
pub fn name(database: Database) -> String

@external(javascript, "../../indexeddb_ffi.mjs", "database_version")
pub fn version(database: Database) -> String

@external(javascript, "../../indexeddb_ffi.mjs", "database_object_store_names")
pub fn object_store_names(database: Database) -> Array(String)

@external(javascript, "../../indexeddb_ffi.mjs", "database_create_object_store")
fn do_create_object_store(
  database: Database,
  name: String,
  options: Json,
) -> Result(ObjectStore, String)

/// This method can be called only within a versionchange transaction.
/// 
/// ## In-Line Out-Of-Line keys
/// https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API/Using_IndexedDB#structuring_the_database
/// 
/// IndexedDB has two ways to handle keys:
/// In-line keys: The key is a property within the stored object itself
/// { id: 1, name: "Alice", email: "alice@example.com" }
/// 
/// Out-of-line keys: The key is stored separately and is not part of the object
/// { name: "Alice", email: "alice@example.com" }
/// 
/// If a key_path is provided then in-line keys are used.
/// Storing simple values, not objects, will require out-of-line keys
/// 
/// Autoincrement and key_path can be used in any combination, though use of the database is affected
/// 
/// If auto_increment is False and you store a value without an id you will get an error.
/// 
/// ## Key vs Index
/// 
/// The key, in-line or out-of-line, is automatically indexed and unique.
/// 
/// Using `add` will fail if inserting a value with a key that already exists.
/// Use `put` to insert or replace a value
pub fn create_object_store(
  database: Database,
  name: String,
  key_path: Option(String),
  auto_increment: Bool,
) -> Result(ObjectStore, String) {
  let entries = [#("autoIncrement", json.bool(auto_increment))]
  let entries = case key_path {
    Some(key_path) -> [#("keyPath", json.string(key_path)), ..entries]
    None -> entries
  }
  do_create_object_store(database, name, json.object(entries))
}

// @external(javascript, "../../indexeddb_ffi.mjs", "database_delete_object_store")
// pub fn delete_object_store(database: Database) -> Array(String)

pub type Mode {
  ReadOnly
  ReadWrite
  ReadWriteFlush
}

fn mode_to_string(mode) {
  case mode {
    ReadOnly -> "readonly"
    ReadWrite -> "readwrite"
    ReadWriteFlush -> "readwriteflush"
  }
}

pub type Durability {
  Strict
  Relaxed
  Default
}

fn durability_to_string(durability) {
  case durability {
    Strict -> "strict"
    Relaxed -> "relaxed"
    Default -> "default"
  }
}

@external(javascript, "../../indexeddb_ffi.mjs", "database_transaction")
fn do_transaction(
  database: Database,
  store_names: Array(String),
  mode: String,
  durability: String,
) -> Result(Transaction, String)

pub fn transaction(
  database: Database,
  store_names: List(String),
  mode: Mode,
  durability: Durability,
) -> Result(Transaction, String) {
  do_transaction(
    database,
    array.from_list(store_names),
    mode_to_string(mode),
    durability_to_string(durability),
  )
}
