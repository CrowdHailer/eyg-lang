import eygir/expression as e
// TODO levels
import eyg/analysis/fast_j

pub type Control {
  E(e.Expression)
  T(fast_j.Type(Int))
}

pub fn step(c, env, eff, tvar, level, bindings, k) {
  case c, k {
    E(exp), k -> try(infer(exp, env, eff, tvar, level, bindings, k))
    T(value), [] -> todo
    // Break(Ok(value))
    T(value), [meta, ..rest] -> try(apply(value, env, k, meta, rest))
  }
}

// No try as we put always a type to continue infiring
// Where do we keep meta for value problably return with T
// stepping out env.
// TODO Probably just keep making textual work -> values for live and rendering lines for effects
// keep a track of index by just adding
// do we push into array fast but I still don't think we build in order without more vars?
// Going fast and function is an odd requirement
pub fn try(_) {
  todo
}

pub fn infer(exp, env, eff, tvar, level, bindings, stack) {
  case exp {
    e.Variable(x) -> #()
  }
}

pub fn apply(_, _, _, _, _) -> Nil {
  todo
}
