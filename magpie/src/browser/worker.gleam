import gleam/io
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/dict
import gleam/json
import gleam/javascript/promise.{try_await}
import magpie/query
import magpie/store/in_memory
import browser/loader
import browser/serialize

// TODO move to plinth
pub type Worker

@external(javascript, "../browser_ffi.mjs", "startWorker")
pub fn start_worker(file: String) -> Worker

@external(javascript, "../browser_ffi.mjs", "postMessage")
pub fn post_message(worker: Worker, message: json.Json) -> Nil

@external(javascript, "../browser_ffi.mjs", "onMessage")
pub fn on_message(worker: Worker, handle: fn(Dynamic) -> a) -> Nil

pub fn run(self: Worker) {
  let db = loader.db()
  let attribute_suggestions =
    dict.to_list(db.attribute_index)
    |> list.map(fn(pair) {
      let #(key, triples) = pair
      #(key, list.length(triples))
    })
  let value_suggestions =
    dict.to_list(db.value_index)
    |> list.filter_map(fn(pair) {
      let #(key, triples) = pair
      case key {
        in_memory.S(value) -> Ok(#(value, list.length(triples)))
        _ -> Error(Nil)
      }
    })
  post_message(
    self,
    serialize.db_view().encode(serialize.DBView(
      list.length(db.triples),
      attribute_suggestions,
    )),
  )

  on_message(self, fn(data) {
    case serialize.query().decode(data) {
      Ok(serialize.Query(from, patterns)) -> {
        let result = query.run(from, patterns, db)
        post_message(self, serialize.relations().encode(result))
      }
      Error(_) -> todo("couldn't decode")
    }
  })
  // This should eventually move to plinth
}
