import gleam/map
// probably the query shouldn't depend on store details
import magpie/store/in_memory.{I, S, Triple}

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
      case map.get(context, var) {
        Ok(constant) -> match_part(Constant(constant), part, context)
        Error(Nil) -> Ok(map.insert(context, var, part))
      }
  }
}

pub fn match_pattern(pattern: Pattern, triple: Triple, context) {
  try context = match_part(pattern.0, I(triple.0), context)
  try context = match_part(pattern.1, S(triple.1), context)
  try context = match_part(pattern.2, triple.2, context)
  Ok(context)
}
