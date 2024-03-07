import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/list
import eygir/annotated as a
import eygir/expression as e

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
  Tag(String)
  Case(Expression, List(#(String, Expression)), Option(Expression))
  Perform(String)
  Builtin(String)
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

    a.Apply(
      #(a.Apply(#(a.Apply(#(a.Case(l), _), branch), _), otherwise), _),
      value,
    ) -> {
      let value = from_annotated(value)
      let #(matches, otherwise) =
        gather_otherwise(otherwise, [#(l, from_annotated(branch))])
      Case(value, matches, otherwise)
    }

    a.Vacant(_) -> Vacant
    a.Variable(var) -> Variable(var)
    a.Integer(value) -> Integer(value)
    a.Binary(value) -> Binary(value)
    a.Str(value) -> String(value)

    a.Tag(label) -> Tag(label)
    a.Perform(label) -> Perform(label)
    a.Builtin(label) -> Builtin(label)

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
    _body -> Function(list.reverse(acc), from_annotated(node))
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

fn gather_otherwise(node, acc) {
  let #(exp, _meta) = node
  case exp {
    a.Apply(#(a.Apply(#(a.Case(l), _), branch), _), otherwise) ->
      gather_otherwise(otherwise, [#(l, from_annotated(branch)), ..acc])
    a.NoCases -> #(list.reverse(acc), None)
    _otherwise -> #(list.reverse(acc), Some(from_annotated(node)))
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

pub fn to_expression(source) {
  case source {
    Variable(x) -> e.Variable(x)
    Call(f, args) ->
      list.fold(args, to_expression(f), fn(acc, arg) {
        let arg = to_expression(arg)
        e.Apply(acc, arg)
      })
    Function(args, body) -> {
      let body = to_expression(body)
      list.fold_right(args, body, fn(acc, arg) {
        let Bind(label) = arg
        e.Lambda(label, acc)
      })
    }
    Block(assigns, then) -> {
      list.fold_right(assigns, to_expression(then), fn(acc, assign) {
        let #(pattern, value) = assign
        let Bind(label) = pattern
        e.Let(label, to_expression(value), acc)
      })
    }
    List(items, tail) -> {
      let tail =
        tail
        |> option.map(to_expression)
        |> option.unwrap(e.Tail)
      list.fold_right(items, tail, fn(acc, item) {
        let item = to_expression(item)
        e.Apply(e.Apply(e.Cons, item), acc)
      })
    }
    Record(fields) -> {
      list.fold_right(fields, e.Empty, fn(acc, field) {
        let #(label, value) = field
        let value = to_expression(value)
        e.Apply(e.Apply(e.Extend(label), value), acc)
      })
    }
    Case(top, matches, otherwise) -> {
      let otherwise =
        otherwise
        |> option.map(to_expression)
        |> option.unwrap(e.NoCases)
      let matches =
        list.fold_right(matches, e.Empty, fn(acc, match) {
          let #(label, value) = match
          let value = to_expression(value)
          e.Apply(e.Apply(e.Case(label), value), acc)
        })
      let top = to_expression(top)
      e.Apply(matches, top)
    }
    Vacant -> e.Vacant("TODO")
    Variable(var) -> e.Variable(var)
    Integer(value) -> e.Integer(value)
    Binary(value) -> e.Binary(value)
    String(value) -> e.Str(value)

    Tag(label) -> e.Tag(label)
    Perform(label) -> e.Perform(label)
    Builtin(identifier) -> e.Builtin(identifier)
  }
}
