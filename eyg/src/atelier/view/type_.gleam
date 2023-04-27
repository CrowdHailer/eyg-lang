// for flat types
import gleam/int
import gleam/list
import gleam/string
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/error

pub fn render_failure(reason, t1, t2) {
  case reason {
    error.TypeMismatch(a, b) ->
      // need to shrink errors together
      string.concat(["Type Missmatch: ", render_type(a), " vs ", render_type(b)])
    error.RowMismatch(label) -> string.append("Row Missmatch: ", label)
    error.MissingVariable(x) -> string.append("missing variable: ", x)
    error.RecursiveType -> "Recursive type"
    error.InvalidTail(_) -> "invalid tail"
  }
}

pub fn render_type(typ) {
  case typ {
    t.Var(i) -> int.to_string(i)
    t.Integer -> "Integer"
    t.String -> "String"
    t.LinkedList(el) -> string.concat(["List(", render_type(el), ")"])
    t.Fun(from, effects, to) ->
      string.concat([
        "(",
        render_type(from),
        ") ->",
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
    _ -> "invalid should not be raw type"
  }
}

fn render_row(r) -> List(String) {
  case r {
    t.Empty -> []
    t.Var(i) -> [string.append("..", int.to_string(i))]
    t.RowExtend(label, value, tail) -> {
      let field = string.concat([label, ": ", render_type(value)])
      [field, ..render_row(tail)]
    }
    _ -> ["not a valid row"]
  }
}

fn render_effects(effects) {
  case effects {
    t.Var(_) | t.Empty -> ""
    t.EffectExtend(label, #(lift, resume), tail) ->
      string.concat([
        " <",
        string.join(
          collect_effect(tail, [render_effect(label, lift, resume)]),
          ", ",
        ),
        ">",
      ])
    _ -> "not a valid effect"
  }
}

fn render_effect(label, lift, resume) {
  string.concat([label, "(", render_type(lift), ", ", render_type(resume), ")"])
}

fn collect_effect(eff, acc) {
  case eff {
    t.EffectExtend(label, #(lift, resume), tail) ->
      collect_effect(tail, [render_effect(label, lift, resume), ..acc])
    _ -> acc
  }
}