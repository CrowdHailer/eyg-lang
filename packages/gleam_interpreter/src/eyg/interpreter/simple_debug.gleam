//// Pretty-printed representation of EYG values.
////
//// Output is laid out by `glam` so that small structures collapse onto a
//// single line and only larger structures break across multiple lines. The
//// returned string is intended for human consumption — applications that
//// need machine-readable output should serialise the value themselves.

import eyg/interpreter/break
import eyg/interpreter/value as v
import glam/doc.{type Document}
import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import multiformats/cid/v1

/// Default width used when none is supplied.
pub const default_width: Int = 80

/// Describe a reason to stop execution.
pub fn describe(reason) -> String {
  case reason {
    break.UndefinedVariable(var) -> "variable undefined: " <> var
    break.UndefinedBuiltin(var) -> "builtin undefined: !" <> var
    break.UndefinedReference(id) -> "reference undefined: #" <> v1.to_string(id)
    break.UndefinedRelease(package, release, _cid) ->
      "release undefined: @" <> package <> ":" <> int.to_string(release)
    break.IncorrectTerm(expected, got) ->
      "unexpected term, expected: " <> expected <> " got: " <> inspect(got)
    break.MissingField(field) -> "missing record field: " <> field
    break.NoMatch(term) -> "no cases matched for: " <> inspect(term)
    break.NotAFunction(term) -> "function expected got: " <> inspect(term)
    break.UnhandledEffect("Abort", reason) ->
      "Aborted with reason: " <> inspect(reason)
    break.UnhandledEffect(effect, lift) ->
      "unhandled effect " <> effect <> "(" <> inspect(lift) <> ")"
    break.Vacant -> "tried to run a todo"
  }
}

/// Inspect a value at the default width.
pub fn inspect(value: v.Value(_, _)) -> String {
  render(value, default_width)
}

/// Render a value with an explicit line-width budget. A larger width keeps
/// more on one line; a smaller width causes earlier breaking.
pub fn render(value: v.Value(_, _), width: Int) -> String {
  value
  |> to_doc
  |> doc.to_string(width)
}

fn to_doc(value: v.Value(_, _)) -> Document {
  case value {
    v.String(s) -> doc.from_string("\"" <> escape_string(s) <> "\"")
    v.Integer(i) -> doc.from_string(int.to_string(i))
    v.Binary(b) -> binary_doc(b)
    v.Tagged(label, inner) ->
      doc.from_string(label)
      |> doc.append(wrap("(", to_doc(inner), ")"))
    v.Record(fields) -> record_doc(fields)
    v.LinkedList(items) -> list_doc(items)
    v.Closure(param, _, _) -> doc.from_string("fn(" <> param <> ") { ... }")
    v.Partial(func, args) -> partial_doc(func, args)
    v.Promise(_) -> doc.from_string("Promise(...)")
  }
}

fn binary_doc(b: BitArray) -> Document {
  let size = bit_array.byte_size(b)
  let encoded = bit_array.base64_encode(b, True)
  doc.from_string("Binary(" <> int.to_string(size) <> " bytes): " <> encoded)
}

fn record_doc(fields) -> Document {
  case dict.is_empty(fields) {
    True -> doc.from_string("{}")
    False -> {
      let entries =
        dict.to_list(fields)
        |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
        |> list.map(fn(pair) {
          let #(key, value) = pair
          doc.from_string(key <> ": ")
          |> doc.append(to_doc(value))
        })
      separated(entries, "{", "}")
    }
  }
}

fn list_doc(items: List(v.Value(_, _))) -> Document {
  case items {
    [] -> doc.from_string("[]")
    _ -> separated(list.map(items, to_doc), "[", "]")
  }
}

fn partial_doc(func, args: List(v.Value(_, _))) -> Document {
  let head = doc.from_string(string.inspect(func))
  case func, args {
    // TODO render the remaining switch branches, remove string.inspect
    // choice of `.field` of `(x) -> { x.field }` for partials without parser representation
    v.Tag(label), [] -> doc.from_string(label)
    _, [] -> wrap("Partial(", head, ")")
    _, _ -> {
      let parts = [head, ..list.map(args, to_doc)]
      let inner =
        parts
        |> doc.join(with: doc.concat([doc.from_string(","), doc.space]))
      wrap("Partial(", inner, ")")
    }
  }
}

/// Wrap a single document between an opening and closing string. Used when
/// the contents have already been laid out (eg. nested Tagged values).
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

/// Lay out a list of items between delimiters. When the contents fit on the
/// current line they appear on one line separated by ", "; otherwise each
/// item appears on its own indented line with a trailing comma.
fn separated(items: List(Document), open: String, close: String) -> Document {
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

fn escape_string(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
}
