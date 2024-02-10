import gleam/io
import gleam/int
import gleam/list
import gleam/string
import eyg/analysis/fast_j as j

pub fn render_type(typ) {
  case typ {
    j.Var(i) -> int.to_string(i)
    j.Integer -> "Integer"
    j.String -> "String"
    j.List(el) -> string.concat(["List(", render_type(el), ")"])
    j.Fun(from, effects, to) ->
      string.concat([
        "(",
        render_type(from),
        ") -> ",
        render_effects(effects),
        " ",
        render_type(to),
      ])
    j.Union(row) ->
      string.concat([
        "[",
        string.concat(
          render_row(row)
          |> list.intersperse(" | "),
        ),
        "]",
      ])
    j.Record(row) ->
      string.concat([
        "{",
        string.concat(
          render_row(row)
          |> list.intersperse(", "),
        ),
        "}",
      ])
    // Rows can be rendered as any mismatch in errors
    j.EffectExtend(_, _, _) -> string.concat(["<", render_effects(typ), ">"])
    row -> {
      string.concat([
        "{",
        render_row(row)
        |> string.join(""),
        "}",
      ])
    }
  }
}

pub fn render_reason(reason) {
  case reason {
    j.MissingVariable(label) ->
      string.concat(["missing variable '", label, "'"])
    j.MissingRow(label) -> string.concat(["missing row '", label, "'"])
    j.TypeMismatch(expected, given) ->
      string.concat([
        "type missmatch given: ",
        render_type(given),
        " expected: ",
        render_type(expected),
      ])
  }
}

fn render_row(r) -> List(String) {
  case r {
    j.Empty -> []
    j.Var(i) -> [string.append("..", int.to_string(i))]
    j.RowExtend(label, value, tail) -> {
      let field = string.concat([label, ": ", render_type(value)])
      [field, ..render_row(tail)]
    }
    _ -> ["not a valid row"]
  }
}

pub fn render_effects(effects) {
  case effects {
    j.Var(i) -> string.concat(["<..", int.to_string(i), ">"])
    j.Empty -> "<>"
    j.EffectExtend(label, #(lift, resume), tail) ->
      string.concat([
        "<",
        string.join(
          collect_effect(tail, [render_effect(label, lift, resume)])
          |> list.reverse,
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
    j.EffectExtend(label, #(lift, resume), tail) ->
      collect_effect(tail, [render_effect(label, lift, resume), ..acc])
    j.Var(i) -> [string.append("..", int.to_string(i)), ..acc]
    j.Empty -> acc
    _ -> {
      io.debug("unexpected effect")
      acc
    }
  }
}
