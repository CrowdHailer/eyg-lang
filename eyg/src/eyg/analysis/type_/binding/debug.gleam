import gleam/io
import gleam/int
import gleam/list
import gleam/string
import eyg/analysis/type_/isomorphic as t
import eyg/analysis/type_/binding/error

pub fn render_type(typ) {
  case typ {
    t.Var(i) -> int.to_string(i)
    t.Integer -> "Integer"
    t.String -> "String"
    t.List(el) -> string.concat(["List(", render_type(el), ")"])
    t.Fun(from, effects, to) ->
      string.concat([
        "(",
        render_type(from),
        ") -> ",
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
    // Rows can be rendered as any mismatch in errors
    t.EffectExtend(_, _, _) -> string.concat(["<", render_effects(typ), ">"])
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
    error.MissingVariable(label) ->
      string.concat(["missing variable '", label, "'"])
    error.MissingRow(label) -> string.concat(["missing row '", label, "'"])
    error.TypeMismatch(expected, given) ->
      string.concat([
        "type missmatch given: ",
        render_type(given),
        " expected: ",
        render_type(expected),
      ])
    error.Recursive -> "Recursive"
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

pub fn render_effects(effects) {
  case effects {
    t.Var(i) -> string.concat(["<..", int.to_string(i), ">"])
    t.Empty -> "<>"
    t.EffectExtend(label, #(lift, resume), tail) ->
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
    t.EffectExtend(label, #(lift, resume), tail) ->
      collect_effect(tail, [render_effect(label, lift, resume), ..acc])
    t.Var(i) -> [string.append("..", int.to_string(i)), ..acc]
    t.Empty -> acc
    _ -> {
      io.debug("unexpected effect")
      acc
    }
  }
}
