import eygir/annotated as a
import gleam/int
import gleam/list
import gleam/string

// this is recursive the tree in eyg is linear what the readability vs efficiency differenct
pub fn lines(source) {
  let #(first, rest) = do_print(source)
  [first, ..rest]
}

fn do_print(source) {
  let #(exp, _meta) = source
  case exp {
    a.Variable(x) -> #(x, [])

    a.Lambda(label, body) -> {
      let #(first, rest) = do_print(body)
      let lines = [
        string.append("└─ ", first),
        ..list.map(rest, string.append("   ", _))
      ]
      let first = string.concat(["function(", label, ")"])
      #(first, lines)
    }
    a.Apply(value, then) -> {
      let #(first, rest) = do_print(then)
      let lines = [
        string.append("└─ ", first),
        ..list.map(rest, string.append("   ", _))
      ]
      let #(first, rest) = do_print(value)
      let rest = [
        string.append("├─ ", first),
        ..list.map(rest, string.append("│  ", _))
      ]
      let first = string.concat(["call"])
      #(first, list.append(rest, lines))
    }
    a.Let(label, value, then) -> {
      let #(first, rest) = do_print(then)
      let lines = [
        string.append("└─ ", first),
        ..list.map(rest, string.append("   ", _))
      ]
      let #(first, rest) = do_print(value)
      let rest = [
        string.append("├─ ", first),
        ..list.map(rest, string.append("│  ", _))
      ]
      let first = string.concat(["let(", label, ")"])
      #(first, list.append(rest, lines))
    }

    a.Vacant -> #("vacant", [])
    a.Integer(value) -> #(int.to_string(value), [])
    a.Str(content) -> #(string.concat(["\"", content, "\""]), [])
    a.Binary(content) -> #(string.inspect(content), [])
    a.Tail -> #("tail", [])
    a.Cons -> #("cons", [])
    a.Empty -> #("empty", [])
    a.Extend(label) -> #(string.concat(["extend(", label, ")"]), [])
    a.Select(label) -> #(string.concat(["select(", label, ")"]), [])
    a.Overwrite(label) -> #(string.concat(["overwrite(", label, ")"]), [])
    a.Tag(label) -> #(string.concat(["tag(", label, ")"]), [])
    a.Case(label) -> #(string.concat(["case(", label, ")"]), [])
    a.NoCases -> #("no cases", [])

    // Effect
    // do/act/effect(effect is a verb and noun)
    a.Perform(label) -> #(string.concat(["perform(", label, ")"]), [])
    a.Handle(label) -> #(string.concat(["handle(", label, ")"]), [])

    a.Builtin(identifier) -> #(string.concat(["builtin(", identifier, ")"]), [])
    a.Reference(identifier) -> #(
      string.concat(["reference(", identifier, ")"]),
      [],
    )
    a.NamedReference(package, release) -> #(
      string.concat(["reference(", package, ", ", int.to_string(release), ")"]),
      [],
    )
  }
}
