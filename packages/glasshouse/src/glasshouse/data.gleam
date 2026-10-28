//// Literal DAG records. Unlike value.decode these readers never execute code.

import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import multiformats/cid/v1

pub fn record(fields: List(#(String, ir.Node(Nil)))) -> ir.Node(Nil) {
  fields
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.fold_right(#(ir.Empty, Nil), fn(rest, field) {
    #(
      ir.Apply(#(ir.Apply(#(ir.Extend(field.0), Nil), field.1), Nil), rest),
      Nil,
    )
  })
}

pub fn fields(
  node: ir.Node(Nil),
) -> Result(List(#(String, ir.Node(Nil))), String) {
  case node {
    #(ir.Empty, _) -> Ok([])
    #(ir.Apply(#(ir.Apply(#(ir.Extend(name), _), value), _), rest), _) -> {
      use fields <- result.try(fields(rest))
      case list.any(fields, fn(field) { field.0 == name }) {
        True -> Error("duplicate data field: " <> name)
        False -> Ok([#(name, value), ..fields])
      }
    }
    _ -> Error("expected a literal record")
  }
}

pub fn field(node, name) {
  use fields <- result.try(fields(node))
  dict.get(dict.from_list(fields), name)
  |> result.replace_error("missing field: " <> name)
}

pub fn text(node) {
  case node {
    #(ir.String(text), _) -> Ok(text)
    _ -> Error("expected a string")
  }
}

pub fn integer(node) {
  case node {
    #(ir.Integer(n), _) -> Ok(n)
    _ -> Error("expected an integer")
  }
}

pub fn link(id: String) -> ir.Node(Nil) {
  let assert Ok(#(cid, _)) = v1.from_string(id)
  #(ir.Reference(ir.Content(cid)), Nil)
}

pub fn reference(node) {
  case node {
    #(ir.Reference(ir.Content(cid)), _) -> Ok(v1.to_string(cid))
    _ -> Error("expected a content reference")
  }
}
