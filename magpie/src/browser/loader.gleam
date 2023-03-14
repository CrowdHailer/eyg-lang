import gleam/dynamic.{Dynamic}
import magpie/store/json
import magpie/store/in_memory

external fn raw_db() -> Dynamic =
  "../db.mjs" "data"

pub fn triples() {
  let assert Ok(triples) = json.decoder()(raw_db())
  triples
}

pub fn db() {
  in_memory.create_db(triples())
}
