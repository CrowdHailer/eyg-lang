import gleam/io
import gleam/dynamic.{Dynamic}
import gleam/list
import gleam/map
import gleam/http.{Get}
import gleam/http/request
import gleam/json
import gleam/fetch
import gleam/javascript/promise.{try_await}
import magpie/query
import magpie/store/in_memory
import browser/loader
import browser/serialize

// move to plinth
pub external type Worker

pub external fn start_worker(String) -> Worker =
  "../browser_ffi.mjs" "startWorker"

pub external fn post_message(Worker, json.Json) -> Nil =
  "../browser_ffi.mjs" "postMessage"

pub external fn on_message(Worker, fn(Dynamic) -> a) -> Nil =
  "../browser_ffi.mjs" "onMessage"

pub external fn log(a) -> Nil =
  "" "console.log"

pub fn run(self: Worker) {
  let db = loader.db()
  let attribute_suggestions =
    map.to_list(db.attribute_index)
    |> list.map(fn(pair) {
      let #(key, triples) = pair
      #(key, list.length(triples))
    })
  let value_suggestions =
    map.to_list(db.value_index)
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

  on_message(
    self,
    fn(data) {
      case serialize.query().decode(data) {
        Ok(serialize.Query(from, patterns)) -> {
          let result = query.run(from, patterns, db)
          post_message(self, serialize.relations().encode(result))
        }
        Error(_) -> todo("couldn't decode")
      }
    },
  )
  // TODO plinth
}
