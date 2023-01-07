import gleam/int
import gleam/list
import gleam/string
import eyg/analysis/typ as t
import eyg/analysis/unification

// Do we have a general need for type debug functionality
pub fn render(type_info) {
  case type_info {
    Ok(t) -> render_type(t)
    Error(f) -> render_failure(f)
  }
}

pub fn render_failure(f) {
  case f {
    unification.TypeMismatch(a, b) ->
      string.concat(["Type Missmatch: ", render_type(a), " vs ", render_type(b)])
    unification.RowMismatch(label) -> string.append("Row Missmatch: ", label)
    unification.MissingVariable(x) -> string.append("missing variable: ", x)
    unification.RecursiveType -> "Recurive type"
  }
}

pub fn render_type(typ) {
  case typ {
    t.Unbound(i) -> int.to_string(i)
    t.Integer -> "Integer"
    t.Binary -> "Binary"
    t.LinkedList(el) -> string.concat(["List(", render_type(el), ")"])
    t.Fun(from, effects, to) ->
      string.concat([
        render_type(from),
        " ->",
        render_effects(effects),
        " ",
        render_type(to),
      ])
    t.Union(row) ->
      string.concat([
        "[",
        string.concat(
          render_row(row)
          |> list.intersperse(" | "),
        ),
        "]",
      ])
    t.Record(row) ->
      string.concat([
        "{",
        string.concat(
          render_row(row)
          |> list.intersperse(", "),
        ),
        "}",
      ])
  }
}

fn render_row(r) -> List(String) {
  case r {
    t.Closed -> []
    t.Open(i) -> [string.append("..", int.to_string(i))]
    t.Extend(label, value, tail) -> {
      let field = string.concat([label, ": ", render_type(value)])
      [field, ..render_row(tail)]
    }
  }
}

fn render_effects(effects) {
  case effects {
    t.Open(_) | t.Closed -> ""
    t.Extend(label, _, tail) -> string.concat([" <", label, ">"])
  }
}
