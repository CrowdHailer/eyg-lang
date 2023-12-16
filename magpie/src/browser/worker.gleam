import gleam/dynamic
import gleam/list
import gleam/dict
import plinth/browser/worker.{type Worker}
import magpie/query
import browser/loader
import browser/serialize

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
    serialize.db_view().encode(serialize.DBView(
      list.length(db.triples),
      attribute_suggestions,
    )),
  )

  worker.on_message(self, fn(data) {
    let data = dynamic.from(data)
    case serialize.query().decode(data) {
      Ok(serialize.Query(from, patterns)) -> {
        let result = query.run(from, patterns, db)
        worker.post_message(self, serialize.relations().encode(result))
      }
      Error(_) -> panic("couldn't decode")
    }
  })
  // This should eventually move to plinth
}
