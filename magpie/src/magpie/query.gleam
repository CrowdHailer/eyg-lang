import gleam/io
import gleam/list
import gleam/dict
import gleam/result
import gleam/string
// probably the query shouldn't depend on store details
import magpie/store/in_memory.{type Triple, B, I, L, S}

pub fn v(var) {
  Variable(var)
}

pub fn b(value) {
  Constant(B(value))
}

pub fn i(value) {
  Constant(I(value))
}

pub fn l(value) {
  Constant(L(value))
}

pub fn s(value) {
  Constant(S(value))
}

pub type Match {
  Variable(String)
  Constant(in_memory.Value)
}

pub type Pattern =
  #(Match, Match, Match)

pub fn match_part(match, part, context) {
  case match {
    Constant(value) ->
      case value == part {
        True -> Ok(context)
        False -> Error(Nil)
      }
    Variable(var) ->
      case dict.get(context, var) {
        Ok(constant) -> match_part(Constant(constant), part, context)
        Error(Nil) -> Ok(dict.insert(context, var, part))
      }
  }
}

pub fn match_pattern(pattern: Pattern, triple: Triple, context) {
  use context <- result.then(match_part(pattern.0, I(triple.0), context))
  use context <- result.then(match_part(pattern.1, S(triple.1), context))
  use context <- result.then(match_part(pattern.2, triple.2, context))
  Ok(context)
}

pub fn single(pattern, db, context) {
  relevant_triples(db, pattern)
  |> list.filter_map(match_pattern(pattern, _, context))
}

pub fn relevant_triples(db: in_memory.DB, pattern) {
  case pattern {
    #(Constant(I(id)), _, _) -> dict.get(db.entity_index, id)
    #(_, Constant(S(attr)), _) -> dict.get(db.attribute_index, attr)
    #(_, _, Constant(value)) -> dict.get(db.value_index, value)
    _ -> Error(Nil)
  }
  |> result.unwrap(db.triples)
}

pub fn where(patterns, db) {
  list.fold(patterns, [dict.new()], fn(contexts, pattern) {
    list.map(contexts, single(pattern, db, _))
    |> list.flatten
  })
}

fn actualize(context: dict.Dict(String, in_memory.Value), find) {
  list.map(find, fn(f) {
    case dict.get(context, f) {
      Ok(r) -> r
      Error(Nil) -> {
        io.debug(
          string.concat(["actualize failed due to invalid find key: ", f]),
        )
        panic("fail")
      }
    }
  })
}

pub fn run(find, patterns, db) {
  where(patterns, db)
  |> list.map(actualize(_, find))
}
