import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import gleam/int
import gleam/io
import gleam/list
import gleam/string

pub fn mono(type_) {
  render_type(type_)
}

pub fn reason(r) {
  render_reason(r)
}

pub fn effect(e) {
  render_effects(e)
}

pub fn render_type(typ) {
  case typ {
    t.Var(i) -> int.to_string(i)
    t.Integer -> "Integer"
    t.Binary -> "Binary"
    t.String -> "String"
    t.List(el) -> "List(" <> render_type(el) <> ")"
    t.Fun(from, eff, to) -> render_function(to, [#(from, eff)])
    t.Union(row) -> string.join(render_row(row), " | ")
    t.Record(row) -> "{" <> string.join(render_row(row), ", ") <> "}"
    // Rows can be rendered as any mismatch in errors
    t.EffectExtend(_, _, _) -> string.concat(["<", render_effects(typ), ">"])
    t.Promise(inner) -> string.concat(["Promise(", render_type(inner), ")"])
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

fn render_function(to, acc) {
  case to {
    t.Fun(from, eff, to) -> render_function(to, [#(from, eff), ..acc])
    _ -> {
      let args = list.reverse(acc)
      let rendered =
        list.map(args, fn(arg) {
          let #(arg, eff) = arg
          let arg = render_type(arg)
          case eff {
            t.Empty -> arg
            _ -> arg <> " <" <> render_effects(eff) <> ">"
          }
        })
      let rendered =
        list.intersperse(rendered, ", ")
        |> string.concat
      "(" <> rendered <> ") -> " <> render_type(to)
    }
  }
}

pub fn render_reason(reason) {
  case reason {
    error.Todo -> "code incomplete"
    error.MissingVariable(label) -> "missing variable '" <> label <> "'"
    error.MissingBuiltin(label) -> "missing variable '!" <> label <> "'"
    error.MissingReference(label) -> "missing reference #" <> label
    error.UndefinedRelease(package, release, _cid) ->
      "release undefined: @" <> package <> ":" <> int.to_string(release)
    error.MissingRow(label) -> "missing row '" <> label <> "'"
    error.TypeMismatch(expected, given) ->
      "type missmatch given: "
      <> render_type(given)
      <> " expected: "
      <> render_type(expected)
    error.Recursive -> "Recursive"
    error.SameTail(expected, given) ->
      "same tail given: "
      <> render_type(given)
      <> " expected: "
      <> render_type(expected)
  }
}

pub fn pretty_reason(reason) {
  render_reason(reason)
}

fn render_row(r) -> List(String) {
  case r {
    t.Empty -> []
    t.Var(i) -> [string.append("..", int.to_string(i))]
    t.RowExtend(label, value, tail) -> {
      let field = string.concat([label, ": ", render_type(value)])
      [field, ..render_row(tail)]
    }
    _ -> ["not a valid row", string.inspect(r)]
  }
}

pub fn render_effects(effects) {
  case effects {
    t.Var(i) -> ".." <> int.to_string(i)
    t.Empty -> ""
    t.EffectExtend(label, #(lift, resume), tail) ->
      string.join(
        collect_effect(tail, [render_effect(label, lift, resume)])
          |> list.reverse,
        ", ",
      )
    _ -> "not a valid effect"
  }
}

fn render_effect(label, lift, resume) {
  string.concat([label, "(↑", render_type(lift), " ↓", render_type(resume), ")"])
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
