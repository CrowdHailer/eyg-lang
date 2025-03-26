import eyg/ir/tree as ir
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
    ir.Variable(x) -> #(x, [])

    ir.Lambda(label, body) -> {
      let #(first, rest) = do_print(body)
      let lines = [
        string.append("└─ ", first),
        ..list.map(rest, string.append("   ", _))
      ]
      let first = string.concat(["function(", label, ")"])
      #(first, lines)
    }
    ir.Apply(value, then) -> {
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
    ir.Let(label, value, then) -> {
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

    ir.Vacant -> #("vacant", [])
    ir.Integer(value) -> #(int.to_string(value), [])
    ir.String(content) -> #(string.concat(["\"", content, "\""]), [])
    ir.Binary(content) -> #(string.inspect(content), [])
    ir.Tail -> #("tail", [])
    ir.Cons -> #("cons", [])
    ir.Empty -> #("empty", [])
    ir.Extend(label) -> #(string.concat(["extend(", label, ")"]), [])
    ir.Select(label) -> #(string.concat(["select(", label, ")"]), [])
    ir.Overwrite(label) -> #(string.concat(["overwrite(", label, ")"]), [])
    ir.Tag(label) -> #(string.concat(["tag(", label, ")"]), [])
    ir.Case(label) -> #(string.concat(["case(", label, ")"]), [])
    ir.NoCases -> #("no cases", [])

    // Effect
    // do/act/effect(effect is a verb and noun)
    ir.Perform(label) -> #(string.concat(["perform(", label, ")"]), [])
    ir.Handle(label) -> #(string.concat(["handle(", label, ")"]), [])

    ir.Builtin(identifier) -> #(
      string.concat(["builtin(", identifier, ")"]),
      [],
    )
    ir.Reference(identifier) -> #(
      string.concat(["reference(", identifier, ")"]),
      [],
    )
    ir.Release(package, release, identifier) -> #(
      string.concat([
        "reference(",
        package,
        ", ",
        int.to_string(release),
        ", ",
        identifier,
        ")",
      ]),
      [],
    )
  }
}
