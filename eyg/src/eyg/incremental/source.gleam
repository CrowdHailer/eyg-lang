import gleam/list
import eygir/expression as e

pub type Expression {
  Var(String)
  Fn(String, Int)
  Let(String, Int, Int)
  Call(Int, Int)
  Integer(Int)
  String(String)
  Tail
  Cons
  Vacant(comment: String)
  Empty
  Extend(label: String)
  Select(label: String)
  Overwrite(label: String)
  Tag(label: String)
  Case(label: String)
  NoCases
  Perform(label: String)
  Handle(label: String)
  Builtin(identifier: String)
}

pub fn do_from_tree(tree, acc) {
  case tree {
    e.Variable(label) -> {
      #(Var(label), acc)
    }
    e.Lambda(label, body) -> {
      let #(node, acc) = do_from_tree(body, acc)
      let index = list.length(acc)
      let acc = [node, ..acc]
      #(Fn(label, index), acc)
    }
    e.Let(label, value, then) -> {
      let #(then, acc) = do_from_tree(then, acc)
      let then_index = list.length(acc)
      let acc = [then, ..acc]
      let #(value, acc) = do_from_tree(value, acc)
      let value_index = list.length(acc)
      let acc = [value, ..acc]

      #(Let(label, value_index, then_index), acc)
    }
    e.Binary(value) -> {
      #(String(value), acc)
    }
    e.Integer(value) -> {
      #(Integer(value), acc)
    }
    _ -> todo("rest of ref")
  }
}

pub fn from_tree(tree) {
  let #(exp, acc) = do_from_tree(tree, [])
  let index = list.length(acc)
  let source = list.reverse([exp, ..acc])
  #(index, source)
}
