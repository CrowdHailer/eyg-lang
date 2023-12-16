import gleam/list
import gleam/dict.{type Dict}
import gleam/option.{None, Some}

pub type Value {
  B(Bool)
  I(Int)
  S(String)
  L(List(Value))
}

pub type Triple =
  #(Int, String, Value)

pub type DB {
  DB(
    triples: List(Triple),
    entity_index: Dict(Int, List(Triple)),
    attribute_index: Dict(String, List(Triple)),
    value_index: Dict(Value, List(Triple)),
  )
}

fn push(current, t) {
  case current {
    None -> [t]
    // added inefficiently to make results of testing not change
    Some(ts) -> list.append(ts, [t])
  }
}

fn index(triples, by) {
  list.fold(triples, dict.new(), fn(acc, t: Triple) {
    dict.update(acc, by(t), push(_, t))
  })
}

pub fn create_db(triples) {
  DB(
    triples,
    index(triples, fn(t: Triple) { t.0 }),
    index(triples, fn(t: Triple) { t.1 }),
    index(triples, fn(t: Triple) { t.2 }),
  )
}
