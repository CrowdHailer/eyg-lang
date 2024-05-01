import eyg/runtime/cast
import eyg/runtime/value as v
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/result.{try}

pub fn do(entries) {
  use items <- result.then(cast.as_list(entries))
  let assert Ok(items) =
    list.try_map(items, fn(value) {
      use name <- result.then(cast.field("name", cast.as_string, value))
      use content <- result.then(cast.field("content", cast.as_binary, value))
      Ok(#(name, content))
    })

  let zipped = promise.map(actual_zip(array.from_list(items)), v.Binary)
  Ok(v.Promise(zipped))
}

pub fn zip(files) {
  actual_zip(array.from_list(files))
}

// can't call zip as global var zip used by import
@external(javascript, "../../../zip_ffi.mjs", "zipItems")
fn actual_zip(items: array.Array(#(String, BitArray))) -> Promise(BitArray)
