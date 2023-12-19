import gleam/dynamic
import gleam/list
import gleam/dict
import gleam_community/codec
import gleam/json
import plinth/browser/worker.{type Worker}
import magpie/query
import magpie/browser/loader
import magpie/browser/serialize

pub fn run(self: Worker) {
  let db = loader.db()
  let attribute_suggestions =
    dict.to_list(db.attribute_index)
    |> list.map(fn(pair) {
      let #(key, triples) = pair
      #(key, list.length(triples))
    })
  // let value_suggestions =
  //   dict.to_list(db.value_index)
  //   |> list.filter_map(fn(pair) {
  //     let #(key, triples) = pair
  //     case key {
  //       in_memory.S(value) -> Ok(#(value, list.length(triples)))
  //       _ -> Error(Nil)
  //     }
  //   })
  worker.post_message(
    self,
    json.string(codec.encode_string(
      serialize.DBView(list.length(db.triples), attribute_suggestions),
      serialize.db_view(),
    )),
  )

  worker.on_message(self, fn(data) {
    let data = dynamic.unsafe_coerce(dynamic.from(data))
    case codec.decode_string(data, serialize.query()) {
      Ok(serialize.Query(from, patterns)) -> {
        let result = query.run(from, patterns, db)
        worker.post_message(
          self,
          json.string(codec.encode_string(result, serialize.relations())),
        )
      }
      Error(_) -> panic("couldn't decode")
    }
  })
  // This should eventually move to plinth
}
