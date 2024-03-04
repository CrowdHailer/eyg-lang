import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/list
import eygir/annotated as a

pub type Pattern {
  Bind(String)
  Destructure(List(#(String, String)))
}

pub type Expression {
  Variable(String)
  Block(List(#(Pattern, Expression)), Expression)
  Call(Expression, List(Expression))
  Function(List(Pattern), Expression)
  Vacant
  Integer(Int)
  Binary(BitArray)
  String(String)
  List(List(Expression), Option(Expression))
  Record(List(#(String, Expression)))
  Overwrite(List(#(String, Expression)), String)
  Tag(String)
  Case(Expression, List(#(String, Expression)), Option(Expression))
  Perform(String)
}

pub fn from_annotated(node) {
  let #(exp, _meta) = node
  case exp {
    a.Lambda(x, body) -> {
      let #(pattern, rest) = gather_destructure(body, x)
      gather_arguments(rest, [pattern])
    }
    a.Let(_x, _value, _then) -> gather_assignments(node, [])
    a.Apply(#(a.Apply(#(a.Cons, _), value), _), rest) ->
      gather_cons(rest, [from_annotated(value)])
    a.Tail -> List([], None)

    a.Apply(#(a.Apply(#(a.Extend(l), _), value), _), rest) ->
      gather_extends(rest, [#(l, from_annotated(value))])
    a.Empty -> Record([])

    a.Apply(#(a.Apply(#(a.Case(l), _), branch), _), otherwise) -> todo

    a.Vacant(_) -> Vacant
    a.Variable(var) -> Variable(var)
    a.Integer(value) -> Integer(value)
    a.Binary(value) -> Binary(value)
    a.Str(value) -> String(value)

    a.Tag(label) -> Tag(label)
    _ -> {
      io.debug(exp)
      panic as "failed from annotated"
    }
  }
}

fn gather_arguments(node, acc) {
  let #(exp, _meta) = node
  case exp {
    a.Lambda(x, body) -> {
      let #(pattern, rest) = gather_destructure(body, x)
      gather_arguments(rest, [pattern, ..acc])
    }
    _ -> panic as "bad arguments"
  }
}

fn gather_destructure(node, var) -> #(Pattern, _) {
  let #(ds, rest) = do_gather_destructure(node, var, [])
  let p = case ds {
    [] -> Bind(var)
    _ -> Destructure(ds)
  }
  #(p, rest)
}

fn do_gather_destructure(node, var, acc) {
  let #(exp, _meta) = node
  case exp {
    a.Let(x, #(a.Apply(#(a.Select(l), _), #(a.Variable(v), _)), _), then) if v == var ->
      do_gather_destructure(then, var, [#(l, x), ..acc])
    _ -> #(list.reverse(acc), node)
  }
}

fn gather_cons(node, acc) {
  let #(exp, _meta) = node
  case exp {
    a.Apply(#(a.Apply(#(a.Cons, _), value), _), rest) ->
      gather_cons(rest, [from_annotated(value), ..acc])
    a.Tail -> List(list.reverse(acc), None)
    _ -> List(list.reverse(acc), Some(from_annotated(node)))
  }
}

fn gather_extends(node, acc) {
  let #(exp, _meta) = node
  case exp {
    a.Apply(#(a.Apply(#(a.Extend(l), _), value), _), rest) ->
      gather_extends(rest, [#(l, from_annotated(value)), ..acc])
    a.Empty -> Record(list.reverse(acc))
    _ -> panic as "bad extend"
  }
}

fn gather_assignments(node, acc) {
  let #(exp, _meta) = node
  case exp {
    a.Let(x, value, then) -> {
      let #(p, then) = gather_destructure(then, x)
      gather_assignments(then, [#(p, from_annotated(value)), ..acc])
    }
    _ -> {
      Block(list.reverse(acc), from_annotated(node))
    }
  }
}
