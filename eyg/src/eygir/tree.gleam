import eygir/expression as e
import gleam/int
import gleam/list
import gleam/string

// this is recursive the tree in eyg is linear what the readability vs efficiency differenct
pub fn lines(source) {
  let #(first, rest) = do_print(source)
  [first, ..rest]
}

fn do_print(source) {
  case source {
    e.Variable(x) -> #(x, [])

    e.Lambda(label, body) -> {
      let #(first, rest) = do_print(body)
      let lines = [
        string.append("└─ ", first),
        ..list.map(rest, string.append("   ", _))
      ]
      let first = string.concat(["function(", label, ")"])
      #(first, lines)
    }
    e.Apply(value, then) -> {
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
    e.Let(label, value, then) -> {
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

    e.Vacant -> #("vacant", [])
    e.Integer(value) -> #(int.to_string(value), [])
    e.Str(content) -> #(string.concat(["\"", content, "\""]), [])
    e.Binary(content) -> #(string.inspect(content), [])
    e.Tail -> #("tail", [])
    e.Cons -> #("cons", [])
    e.Empty -> #("empty", [])
    e.Extend(label) -> #(string.concat(["extend(", label, ")"]), [])
    e.Select(label) -> #(string.concat(["select(", label, ")"]), [])
    e.Overwrite(label) -> #(string.concat(["overwrite(", label, ")"]), [])
    e.Tag(label) -> #(string.concat(["tag(", label, ")"]), [])
    e.Case(label) -> #(string.concat(["case(", label, ")"]), [])
    e.NoCases -> #("no cases", [])

    // Effect
    // do/act/effect(effect is a verb and noun)
    e.Perform(label) -> #(string.concat(["perform(", label, ")"]), [])
    e.Handle(label) -> #(string.concat(["handle(", label, ")"]), [])
    // Experiment in stateful Effects
    e.Shallow(label) -> #(string.concat(["shallow(", label, ")"]), [])

    e.Builtin(identifier) -> #(string.concat(["builtin(", identifier, ")"]), [])
    e.Reference(identifier) -> #(
      string.concat(["reference(", identifier, ")"]),
      [],
    )
    e.NamedReference(package, release) -> #(
      string.concat(["reference(", package, ", ", int.to_string(release), ")"]),
      [],
    )
  }
}
