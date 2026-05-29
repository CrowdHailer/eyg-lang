import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import glam/doc.{type Document}
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import multiformats/cid/v1

const default_width: Int = 80

pub fn mono(type_) {
  render_type(type_)
}

pub fn reason(r) {
  render_reason(r)
}

pub fn effect(e) {
  render_effects(e)
}

pub fn render(typ, width: Int) -> String {
  typ
  |> to_doc
  |> doc.to_string(width)
}

pub fn render_type(typ) {
  render(typ, default_width)
}

fn to_doc(typ) -> Document {
  case typ {
    t.Var(i) -> doc.from_string(int.to_string(i))
    t.Integer -> doc.from_string("Integer")
    t.Binary -> doc.from_string("Binary")
    t.String -> doc.from_string("String")
    t.Never -> doc.from_string("Never")
    t.List(el) -> wrap("List(", to_doc(el), ")")
    t.Fun(from, eff, to) -> function_doc(to, [#(from, eff)])
    t.Union(row) ->
      wrap("[", row_docs(row) |> doc.join(with: doc.break(" | ", " |")), "]")
    t.Record(row) -> separated(row_docs(row), "{", "}")
    // Rows can be rendered as any mismatch in errors
    t.EffectExtend(_, _, _) -> wrap("<", effects_doc(typ), ">")
    t.Promise(inner) -> wrap("Promise(", to_doc(inner), ")")
    row -> {
      wrap("{", row_docs(row) |> doc.join(with: doc.from_string("")), "}")
    }
  }
}

fn function_doc(to, acc) {
  case to {
    t.Fun(from, eff, to) -> function_doc(to, [#(from, eff), ..acc])
    _ -> {
      let args = list.reverse(acc)
      let rendered = list.map(args, argument_doc)
      separated(rendered, "(", ")")
      |> doc.append(doc.from_string(" -> "))
      |> doc.append(to_doc(to))
    }
  }
}

fn argument_doc(arg) -> Document {
  let #(arg, eff) = arg
  case eff {
    // assumes resolved TODO remove and use the open close code
    // t.Var(_) -> arg
    t.Empty -> to_doc(arg)
    _ ->
      to_doc(arg)
      |> doc.append(doc.space)
      |> doc.append(wrap("<", effects_doc(eff), ">"))
  }
}

pub fn render_reason(reason) {
  case reason {
    error.Todo -> "code incomplete"
    error.MissingVariable(label) -> "missing variable '" <> label <> "'"
    error.MissingBuiltin(label) -> "missing variable '!" <> label <> "'"
    error.MissingReference(label) ->
      "missing reference #" <> v1.to_string(label)
    error.UndefinedRelease(package, release, _cid) ->
      "release undefined: @" <> package <> ":" <> int.to_string(release)
    error.MissingRow(label) -> "missing row '" <> label <> "'"
    error.TypeMismatch(expected, given) ->
      "type mismatch given: "
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

pub fn hint(reason) {
  case reason {
    error.Todo -> "this expression is not yet implemented"
    error.MissingVariable(label) -> "check '" <> label <> "' is defined"
    error.MissingBuiltin(label) -> "check the builtin '!" <> label <> "' exists"
    error.MissingReference(_) -> "the referenced module is not available"
    error.UndefinedRelease(_, _, _) -> "the package release is not available"
    error.MissingRow(label) ->
      "the record or union is missing '" <> label <> "'"
    error.TypeMismatch(_expected, _given) ->
      "check the expression matches the expected type"
    error.Recursive ->
      "this expression has a recursive type which is not supported"
    error.SameTail(_, _) -> "the row tails must be different"
  }
}

fn row_docs(r) -> List(Document) {
  case r {
    t.Empty -> []
    t.Var(i) -> [doc.from_string(string.append("..", int.to_string(i)))]
    t.RowExtend(label, value, tail) -> {
      let field =
        doc.from_string(label <> ": ")
        |> doc.append(to_doc(value))
      [field, ..row_docs(tail)]
    }
    _ -> [
      doc.from_string("not a valid row"),
      doc.from_string(string.inspect(r)),
    ]
  }
}

pub fn render_effects(effects) {
  effects_doc(effects)
  |> doc.to_string(default_width)
}

fn effects_doc(effects) -> Document {
  case effects {
    t.Var(i) -> doc.from_string(".." <> int.to_string(i))
    t.Empty -> doc.from_string("")
    t.EffectExtend(label, #(lift, resume), tail) ->
      collect_effect(tail, [effect_doc(label, lift, resume)])
      |> list.reverse
      |> doc.join(with: doc.break(", ", ","))
    _ -> doc.from_string("not a valid effect")
  }
}

fn effect_doc(label, lift, resume) -> Document {
  doc.concat([
    doc.from_string(label <> "(↑"),
    to_doc(lift),
    doc.from_string(" ↓"),
    to_doc(resume),
    doc.from_string(")"),
  ])
}

fn collect_effect(eff, acc: List(Document)) {
  case eff {
    t.EffectExtend(label, #(lift, resume), tail) ->
      collect_effect(tail, [effect_doc(label, lift, resume), ..acc])
    t.Var(i) -> [doc.from_string(string.append("..", int.to_string(i))), ..acc]
    t.Empty -> acc
    _ -> {
      io.println("unexpected effect")
      acc
    }
  }
}

fn wrap(open: String, inner: Document, close: String) -> Document {
  doc.concat([
    doc.from_string(open),
    doc.soft_break
      |> doc.append(inner)
      |> doc.nest(by: 2),
    doc.soft_break,
    doc.from_string(close),
  ])
  |> doc.group
}

fn separated(items: List(Document), open: String, close: String) -> Document {
  case items {
    [] -> doc.from_string(open <> close)
    _ -> {
      let separator = doc.break(", ", ",")
      let body = doc.join(items, with: separator)
      let inner =
        doc.soft_break
        |> doc.append(body)
        |> doc.nest(by: 2)

      doc.concat([
        doc.from_string(open),
        inner,
        doc.break("", ","),
        doc.from_string(close),
      ])
      |> doc.group
    }
  }
}
