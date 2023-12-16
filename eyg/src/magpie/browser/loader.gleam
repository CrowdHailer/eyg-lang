import gleam/dynamic.{type Dynamic}
import magpie/store/json
import magpie/store/in_memory

@external(javascript, "../db.mjs", "data")
fn raw_db() -> Dynamic

pub fn triples() {
  let assert Ok(triples) = json.decoder()(raw_db())
  triples
}

pub fn db() {
  in_memory.create_db(triples())
}
