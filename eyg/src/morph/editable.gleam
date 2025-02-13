import eyg/ir/tree as ir
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}

pub type Pattern {
  Bind(String)
  Destructure(List(#(String, String)))
}

pub type Expression {
  Variable(String)
  Block(List(#(Pattern, Expression)), Expression, open: Bool)
  Call(Expression, List(Expression))
  Function(List(Pattern), Expression)
  Vacant
  Integer(Int)
  Binary(BitArray)
  String(String)
  List(List(Expression), Option(Expression))
  Record(List(#(String, Expression)), Option(Expression))
  Select(Expression, String)
  Tag(String)
  Case(Expression, List(#(String, Expression)), Option(Expression))
  Perform(String)
  Deep(String)
  Builtin(String)
  Reference(String)
  Release(package: String, release: Int, identifer: String)
}

pub type Assignments =
  List(#(Pattern, Expression))

pub fn open_assignments(assignments) {
  list.map(assignments, fn(a) {
    let #(pattern, value) = a
    #(pattern, open_all(value))
  })
}

pub fn open_all(source) {
  case source {
    Block(assignments, then, _) -> {
      let assignments = open_assignments(assignments)
      let then = open_all(then)
      Block(assignments, then, True)
    }
    Call(func, args) -> {
      let func = open_all(func)
      let args = list.map(args, open_all)
      Call(func, args)
    }
    Function(patterns, body) -> {
      Function(patterns, open_all(body))
    }
    List(elements, tail) -> {
      let elements = list.map(elements, open_all)
      let tail = option.map(tail, open_all)
      List(elements, tail)
    }
    Record(fields, overwrite) -> {
      let fields =
        list.map(fields, fn(a) {
          let #(label, value) = a
          #(label, open_all(value))
        })
      let overwrite = option.map(overwrite, open_all)
      Record(fields, overwrite)
    }
    Select(from, label) -> {
      Select(open_all(from), label)
    }
    Case(value, matches, otherwise) -> {
      let value = open_all(value)
      let matches =
        list.map(matches, fn(a) {
          let #(label, value) = a
          #(label, open_all(value))
        })
      let otherwise = option.map(otherwise, open_all)
      Case(value, matches, otherwise)
    }
    _ -> source
  }
}

pub fn from_annotated(node) {
  let #(exp, _meta) = node
  case exp {
    ir.Lambda(x, body) -> {
      let #(pattern, rest) = gather_destructure(body, x)
      gather_parameters(rest, [pattern])
    }
    ir.Let(_x, _value, _then) -> gather_assignments(node, [], False)
    ir.Apply(#(ir.Apply(#(ir.Cons, _), value), _), rest) ->
      gather_cons(rest, [from_annotated(value)])
    ir.Tail -> List([], None)
    ir.Cons -> {
      io.debug("bare cons")
      panic
    }

    ir.Apply(#(ir.Apply(#(ir.Extend(l), _), value), _), rest) ->
      gather_extends(rest, [#(l, from_annotated(value))])
    ir.Empty -> Record([], None)
    ir.Extend(_) -> {
      io.debug("bare extend")
      panic
    }

    ir.Apply(#(ir.Apply(#(ir.Overwrite(l), _), value), _), rest) ->
      gather_overwrite(rest, [#(l, from_annotated(value))])
    ir.Overwrite(_) -> {
      io.debug("bare overwrite")
      panic
    }

    ir.Apply(#(ir.Select(label), _), from) ->
      Select(from_annotated(from), label)
    ir.Select(label) -> Function([Bind("$")], Select(Variable("$"), label))

    ir.Apply(
      #(ir.Apply(#(ir.Apply(#(ir.Case(l), _), branch), _), otherwise), _),
      value,
    ) -> {
      let value = from_annotated(value)
      let #(matches, otherwise) =
        gather_otherwise(otherwise, [#(l, from_annotated(branch))])
      Case(value, matches, otherwise)
    }
    ir.Apply(#(ir.Apply(#(ir.Case(l), _), branch), _), otherwise) -> {
      let #(matches, otherwise) =
        gather_otherwise(otherwise, [#(l, from_annotated(branch))])
      Function([Bind("$")], Case(Variable("$"), matches, otherwise))
    }
    ir.Case(_) -> {
      io.debug("bare case")
      Variable("CASE!!")
    }
    ir.NoCases -> {
      io.debug("bare nocases")
      Variable("NOCASE!!")
    }

    ir.Apply(func, arg) -> {
      let arg = from_annotated(arg)
      case from_annotated(func) {
        Call(func, args) -> Call(func, list.append(args, [arg]))
        other -> Call(other, [arg])
      }
      // gather_arguments(func, [from_annotated(arg)])
    }

    ir.Vacant -> Vacant
    ir.Variable(var) -> Variable(var)
    ir.Integer(value) -> Integer(value)
    ir.Binary(value) -> Binary(value)
    ir.String(value) -> String(value)

    ir.Tag(label) -> Tag(label)
    ir.Perform(label) -> Perform(label)
    ir.Handle(label) -> Deep(label)

    ir.Builtin(identifier) -> Builtin(identifier)
    ir.Reference(identifier) -> Reference(identifier)
    ir.Release(package, release, id) -> Release(package, release, id)
  }
}

fn gather_parameters(node, acc) {
  let #(exp, _meta) = node
  case exp {
    ir.Lambda(x, body) -> {
      let #(pattern, rest) = gather_destructure(body, x)
      gather_parameters(rest, [pattern, ..acc])
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
  case is_free(var, rest) {
    True -> #(Bind(var), node)
    False -> #(p, rest)
  }
}

// TODO move to better home
fn is_free(x, source) {
  let #(exp, _) = source
  case exp {
    ir.Variable(var) -> x == var
    ir.Lambda(param, _body) if param == x -> False
    ir.Lambda(_param, body) -> is_free(x, body)
    ir.Apply(func, arg) -> is_free(x, func) || is_free(x, arg)
    ir.Let(var, value, _then) if var == x -> is_free(x, value)
    ir.Let(_var, value, then) -> is_free(x, value) || is_free(x, then)
    _ -> False
  }
}

fn do_gather_destructure(node, var, acc) {
  let #(exp, _meta) = node
  case exp {
    ir.Let(x, #(ir.Apply(#(ir.Select(l), _), #(ir.Variable(v), _)), _), then)
      if v == var
    -> do_gather_destructure(then, var, [#(l, x), ..acc])
    _ -> #(list.reverse(acc), node)
  }
}

fn gather_cons(node, acc) {
  let #(exp, _meta) = node
  case exp {
    ir.Apply(#(ir.Apply(#(ir.Cons, _), value), _), rest) ->
      gather_cons(rest, [from_annotated(value), ..acc])
    ir.Tail -> List(list.reverse(acc), None)
    _ -> List(list.reverse(acc), Some(from_annotated(node)))
  }
}

fn gather_extends(node, acc) {
  let #(exp, _meta) = node
  case exp {
    ir.Apply(#(ir.Apply(#(ir.Extend(l), _), value), _), rest) ->
      gather_extends(rest, [#(l, from_annotated(value)), ..acc])
    ir.Empty -> Record(list.reverse(acc), None)
    // _ -> panic as "bad extend"
    _ -> Record(list.reverse(acc), Some(Variable("Record extend")))
  }
}

fn gather_overwrite(node, acc) {
  let #(exp, _meta) = node
  case exp {
    ir.Apply(#(ir.Apply(#(ir.Overwrite(l), _), value), _), rest) ->
      gather_overwrite(rest, [#(l, from_annotated(value)), ..acc])
    _ -> Record(list.reverse(acc), Some(from_annotated(node)))
  }
}

fn gather_otherwise(node, acc) {
  let #(exp, _meta) = node
  case exp {
    ir.Apply(#(ir.Apply(#(ir.Case(l), _), branch), _), otherwise) ->
      gather_otherwise(otherwise, [#(l, from_annotated(branch)), ..acc])
    ir.NoCases -> #(list.reverse(acc), None)
    _otherwise -> #(list.reverse(acc), Some(from_annotated(node)))
  }
}

pub fn gather_assignments(node, acc, open) {
  let #(exp, _meta) = node
  case exp {
    ir.Let(x, value, then) -> {
      let #(p, then) = gather_destructure(then, x)
      gather_assignments(then, [#(p, from_annotated(value)), ..acc], open)
    }
    _ -> {
      Block(list.reverse(acc), from_annotated(node), open)
    }
  }
}

fn gather_arguments(func, args) {
  case func {
    #(ir.Apply(func, arg), _) ->
      gather_arguments(func, [from_annotated(arg), ..args])
    // don't reverse args as gathers from the outside in
    _ -> Call(from_annotated(func), args)
  }
}

fn pattern_to_annotated(p, exp, rev) {
  case p {
    Bind(label) -> #(label, exp)
    Destructure(ds) -> {
      let exp =
        list.fold_right(ds, exp, fn(acc, d) {
          let #(label, var) = d
          #(
            ir.Let(
              var,
              #(
                ir.Apply(#(ir.Select(label), rev), #(ir.Variable("$"), rev)),
                rev,
              ),
              acc,
            ),
            rev,
          )
        })
      #("$", exp)
    }
  }
}

pub fn to_annotated(source, rev) {
  case source {
    Variable(x) -> #(ir.Variable(x), rev)
    Call(f, args) ->
      list.index_fold(args, to_annotated(f, [0, ..rev]), fn(acc, arg, i) {
        let arg = to_annotated(arg, [i + 1, ..rev])
        #(ir.Apply(acc, arg), rev)
      })
    Function(args, body) -> {
      let len = list.length(args)
      let body = to_annotated(body, [len, ..rev])
      case args, body {
        [Bind("$")], #(ir.Apply(inner, #(ir.Variable("$"), _)), _) -> inner
        _, _ -> {
          let assert #(0, exp) =
            list.fold_right(args, #(len, body), fn(acc, arg) {
              let #(i, acc) = acc
              // start on body index
              let i = i - 1
              let #(var, body) = pattern_to_annotated(arg, acc, [i, ..rev])
              #(i, #(ir.Lambda(var, body), rev))
            })
          exp
        }
      }
    }
    Block(assigns, then, _) -> {
      let len = list.length(assigns)
      let assert #(0, exp) =
        list.fold_right(
          assigns,
          #(len, to_annotated(then, [len, ..rev])),
          fn(acc, assign) {
            let #(i, acc) = acc
            let i = i - 1
            let #(pattern, value) = assign
            let #(var, acc) = pattern_to_annotated(pattern, acc, [i, ..rev])
            #(
              i,
              #(ir.Let(var, to_annotated(value, [1, i, ..rev]), acc), [i, ..rev]),
            )
          },
        )
      exp
    }
    List(items, tail) -> {
      let len = list.length(items)
      let tail =
        tail
        |> option.map(to_annotated(_, [len, ..rev]))
        |> option.unwrap(#(ir.Tail, [len, ..rev]))
      let assert #(0, exp) =
        list.fold_right(items, #(len, tail), fn(acc, item) {
          let #(i, acc) = acc
          let i = i - 1

          let item = to_annotated(item, [i, ..rev])
          #(i, #(ir.Apply(#(ir.Apply(#(ir.Cons, rev), item), rev), acc), rev))
        })
      exp
    }
    Record(fields, rest) -> {
      let len = list.length(fields) * 2
      let #(build, rest) = case rest {
        None -> #(ir.Extend, #(ir.Empty, rev))
        Some(original) -> #(ir.Overwrite, to_annotated(original, [len, ..rev]))
      }
      let assert #(0, exp) =
        list.fold_right(fields, #(len, rest), fn(acc, field) {
          let #(i, acc) = acc
          let i = i - 2
          let #(label, value) = field
          let value = to_annotated(value, [i + 1, ..rev])
          #(i, #(
            ir.Apply(#(ir.Apply(#(build(label), [i, ..rev]), value), rev), acc),
            rev,
          ))
        })
      exp
    }
    Select(from, label) -> {
      #(
        ir.Apply(
          #(ir.Select(label), [0, ..rev]),
          to_annotated(from, [1, ..rev]),
        ),
        rev,
      )
    }

    Case(top, matches, otherwise) -> {
      let len = list.length(matches)
      let otherwise = case otherwise {
        Some(otherwise) -> to_annotated(otherwise, [len + 1, ..rev])
        None -> #(ir.NoCases, [len + 1, ..rev])
      }
      let assert #(1, matches) =
        list.fold_right(matches, #(len + 1, otherwise), fn(acc, match) {
          let #(i, acc) = acc
          let i = i - 1
          let #(label, branch) = match
          let branch = to_annotated(branch, [0, i, ..rev])
          let acc = #(
            ir.Apply(#(ir.Apply(#(ir.Case(label), rev), branch), rev), acc),
            rev,
          )
          #(i, acc)
        })
      let top = to_annotated(top, [0, ..rev])

      let exp = ir.Apply(matches, top)
      #(exp, rev)
    }
    Vacant -> #(ir.Vacant, rev)
    Integer(value) -> #(ir.Integer(value), rev)
    Binary(value) -> #(ir.Binary(value), rev)
    String(value) -> #(ir.String(value), rev)

    Tag(label) -> #(ir.Tag(label), rev)
    Perform(label) -> #(ir.Perform(label), rev)
    Deep(label) -> #(ir.Handle(label), rev)
    Builtin(identifier) -> #(ir.Builtin(identifier), rev)
    Reference(identifier) -> #(ir.Reference(identifier), rev)
    Release(package, release, id) -> #(ir.Release(package, release, id), rev)
  }
}
