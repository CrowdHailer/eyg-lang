import gleam/list
import gleam/map.{Map}
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
    entity_index: Map(Int, List(Triple)),
    attribute_index: Map(String, List(Triple)),
    value_index: Map(Value, List(Triple)),
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
  list.fold(
    triples,
    map.new(),
    fn(acc, t: Triple) { map.update(acc, by(t), push(_, t)) },
  )
}

pub fn create_db(triples) {
  DB(
    triples,
    index(triples, fn(t: Triple) { t.0 }),
    index(triples, fn(t: Triple) { t.1 }),
    index(triples, fn(t: Triple) { t.2 }),
  )
}
