//// Parse EYG source text into its Abstract Syntax Tree.
////
//// The AST is the canonical flat representation

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import multiformats/cid/v1

pub const label = "EYGParse"

pub fn lift() {
  t.String
}

pub fn lower() {
  t.result(t.ast(), t.String)
}

pub fn decode(lift) {
  cast.as_string(lift)
}

pub fn encode(result: Result(ir.Node(m), String)) -> v.Value(a, b) {
  case result {
    Ok(node) -> v.ok(v.LinkedList(flatten(node, [])))
    Error(message) -> v.error(v.String(message))
  }
}

fn tagged(tag, attribute) {
  v.Tagged(tag, attribute)
}

/// Pre-order flatten a node onto `rest`. Children are appended after the node
/// in left-to-right order.
fn flatten(node: ir.Node(m), rest: List(v.Value(a, b))) -> List(v.Value(a, b)) {
  let #(expression, _meta) = node
  case expression {
    ir.Variable(label) -> [tagged("Variable", v.String(label)), ..rest]
    ir.Lambda(label, body) -> [
      tagged("Lambda", v.String(label)),
      ..flatten(body, rest)
    ]
    ir.Apply(function, argument) -> [
      tagged("Apply", v.unit()),
      ..flatten(function, flatten(argument, rest))
    ]
    ir.Let(label, value, then) -> [
      tagged("Let", v.String(label)),
      ..flatten(value, flatten(then, rest))
    ]
    ir.Binary(value) -> [tagged("Binary", v.Binary(value)), ..rest]
    ir.Integer(value) -> [tagged("Integer", v.Integer(value)), ..rest]
    ir.String(value) -> [tagged("String", v.String(value)), ..rest]
    ir.Tail -> [tagged("Tail", v.unit()), ..rest]
    ir.Cons -> [tagged("Cons", v.unit()), ..rest]
    ir.Vacant -> [tagged("Vacant", v.unit()), ..rest]
    ir.Empty -> [tagged("Empty", v.unit()), ..rest]
    ir.Extend(label) -> [tagged("Extend", v.String(label)), ..rest]
    ir.Select(label) -> [tagged("Select", v.String(label)), ..rest]
    ir.Overwrite(label) -> [tagged("Overwrite", v.String(label)), ..rest]
    ir.Tag(label) -> [tagged("Tag", v.String(label)), ..rest]
    ir.Case(label) -> [tagged("Case", v.String(label)), ..rest]
    ir.NoCases -> [tagged("NoCases", v.unit()), ..rest]
    ir.Perform(label) -> [tagged("Perform", v.String(label)), ..rest]
    ir.Handle(label) -> [tagged("Handle", v.String(label)), ..rest]
    ir.Builtin(identifier) -> [tagged("Builtin", v.String(identifier)), ..rest]
    ir.ContentReference(identifier) -> [
      tagged("ContentReference", v.String(v1.to_string(identifier))),
      ..rest
    ]
    ir.ReleaseReference(package, version, identifier) -> [
      tagged(
        "ReleaseReference",
        v.Record(
          dict.from_list([
            #("package", v.String(package)),
            #("version", v.Integer(version)),
            #("cid", v.String(v1.to_string(identifier))),
          ]),
        ),
      ),
      ..rest
    ]
    ir.RelativeReference(location) -> [
      tagged("RelativeReference", v.String(location)),
      ..rest
    ]
  }
}
