import eygir/annotated as a
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
  Vacant(comment: String)
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
  Shallow(String)
  Builtin(String)
  Reference(String)
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

pub fn from_expression(exp) {
  from_annotated(a.add_annotation(exp, Nil))
}

pub fn from_annotated(node) {
  let #(exp, _meta) = node
  case exp {
    a.Lambda(x, body) -> {
      let #(pattern, rest) = gather_destructure(body, x)
      gather_parameters(rest, [pattern])
    }
    a.Let(_x, _value, _then) -> gather_assignments(node, [], False)
    a.Apply(#(a.Apply(#(a.Cons, _), value), _), rest) ->
      gather_cons(rest, [from_annotated(value)])
    a.Tail -> List([], None)
    a.Cons -> {
      io.debug("bare cons")
      panic
    }

    a.Apply(#(a.Apply(#(a.Extend(l), _), value), _), rest) ->
      gather_extends(rest, [#(l, from_annotated(value))])
    a.Empty -> Record([], None)
    a.Extend(_) -> {
      io.debug("bare extend")
      panic
    }

    a.Apply(#(a.Apply(#(a.Overwrite(l), _), value), _), rest) ->
      gather_overwrite(rest, [#(l, from_annotated(value))])
    a.Overwrite(_) -> {
      io.debug("bare overwrite")
      panic
    }

    a.Apply(#(a.Select(label), _), from) -> Select(from_annotated(from), label)
    a.Select(label) -> Function([Bind("$")], Select(Variable("$"), label))

    a.Apply(
      #(a.Apply(#(a.Apply(#(a.Case(l), _), branch), _), otherwise), _),
      value,
    ) -> {
      let value = from_annotated(value)
      let #(matches, otherwise) =
        gather_otherwise(otherwise, [#(l, from_annotated(branch))])
      Case(value, matches, otherwise)
    }
    a.Apply(#(a.Apply(#(a.Case(l), _), branch), _), otherwise) -> {
      let #(matches, otherwise) =
        gather_otherwise(otherwise, [#(l, from_annotated(branch))])
      Function([Bind("$")], Case(Variable("$"), matches, otherwise))
    }
    a.Case(_) -> {
      io.debug("bare case")
      Variable("CASE!!")
    }
    a.NoCases -> {
      io.debug("bare nocases")
      Variable("NOCASE!!")
    }

    a.Apply(func, arg) -> {
      let arg = from_annotated(arg)
      case from_annotated(func) {
        Call(func, args) -> Call(func, list.append(args, [arg]))
        other -> Call(other, [arg])
      }
      // gather_arguments(func, [from_annotated(arg)])
    }

    a.Vacant(comment) -> Vacant(comment)
    a.Variable(var) -> Variable(var)
    a.Integer(value) -> Integer(value)
    a.Binary(value) -> Binary(value)
    a.Str(value) -> String(value)

    a.Tag(label) -> Tag(label)
    a.Perform(label) -> Perform(label)
    a.Handle(label) -> Deep(label)
    a.Shallow(label) -> Shallow(label)

    a.Builtin(identifier) -> Builtin(identifier)
    a.Reference(identifier) -> Reference(identifier)
  }
}

fn gather_parameters(node, acc) {
  let #(exp, _meta) = node
  case exp {
    a.Lambda(x, body) -> {
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
    a.Variable(var) -> x == var
    a.Lambda(param, _body) if param == x -> False
    a.Lambda(_param, body) -> is_free(x, body)
    a.Apply(func, arg) -> is_free(x, func) || is_free(x, arg)
    a.Let(var, value, _then) if var == x -> is_free(x, value)
    a.Let(_var, value, then) -> is_free(x, value) || is_free(x, then)
    _ -> False
  }
}

fn do_gather_destructure(node, var, acc) {
  let #(exp, _meta) = node
  case exp {
    a.Let(x, #(a.Apply(#(a.Select(l), _), #(a.Variable(v), _)), _), then)
      if v == var
    -> do_gather_destructure(then, var, [#(l, x), ..acc])
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
    a.Empty -> Record(list.reverse(acc), None)
    // _ -> panic as "bad extend"
    _ -> Record(list.reverse(acc), Some(Variable("Record extend")))
  }
}

fn gather_overwrite(node, acc) {
  let #(exp, _meta) = node
  case exp {
    a.Apply(#(a.Apply(#(a.Overwrite(l), _), value), _), rest) ->
      gather_overwrite(rest, [#(l, from_annotated(value)), ..acc])
    _ -> Record(list.reverse(acc), Some(from_annotated(node)))
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

pub fn gather_assignments(node, acc, open) {
  let #(exp, _meta) = node
  case exp {
    a.Let(x, value, then) -> {
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
    #(a.Apply(func, arg), _) ->
      gather_arguments(func, [from_annotated(arg), ..args])
    // don't reverse args as gathers from the outside in
    _ -> Call(from_annotated(func), args)
  }
}

// fn pattern_to_expression(p, exp) {
//   case p {
//     Bind(label) -> #(label, exp)
//     Destructure(ds) -> {
//       let exp =
//         list.fold_right(ds, exp, fn(acc, d) {
//           let #(label, var) = d
//           e.Let(var, e.Apply(e.Select(label), e.Variable("$")), acc)
//         })
//       #("$", exp)
//     }
//   }
// }

pub fn to_expression(source) {
  to_annotated(source, [])
  |> a.drop_annotation
  // case source {
  //   Variable(x) -> e.Variable(x)
  //   Call(f, args) ->
  //     list.fold(args, to_expression(f), fn(acc, arg) {
  //       let arg = to_expression(arg)
  //       e.Apply(acc, arg)
  //     })
  //   Function(args, body) -> {
  //     let body = to_expression(body)
  //     list.fold_right(args, body, fn(acc, arg) {
  //       let #(var, body) = pattern_to_expression(arg, acc)
  //       e.Lambda(var, body)
  //     })
  //   }
  //   Block(assigns, then) -> {
  //     list.fold_right(assigns, to_expression(then), fn(acc, assign) {
  //       let #(pattern, value) = assign
  //       let #(var, acc) = pattern_to_expression(pattern, acc)
  //       e.Let(var, to_expression(value), acc)
  //     })
  //   }
  //   List(items, tail) -> {
  //     let tail =
  //       tail
  //       |> option.map(to_expression)
  //       |> option.unwrap(e.Tail)
  //     list.fold_right(items, tail, fn(acc, item) {
  //       let item = to_expression(item)
  //       e.Apply(e.Apply(e.Cons, item), acc)
  //     })
  //   }

  //   Record(fields, None) -> {
  //     list.fold_right(fields, e.Empty, fn(acc, field) {
  //       let #(label, value) = field
  //       let value = to_expression(value)
  //       e.Apply(e.Apply(e.Extend(label), value), acc)
  //     })
  //   }
  //   Record(fields, Some(original)) -> {
  //     list.fold_right(fields, to_expression(original), fn(acc, field) {
  //       let #(label, value) = field
  //       let value = to_expression(value)
  //       e.Apply(e.Apply(e.Overwrite(label), value), acc)
  //     })
  //   }
  //   Select(from, label) -> e.Apply(e.Select(label), to_expression(from))

  //   Case(top, matches, otherwise) -> {
  //     let otherwise =
  //       otherwise
  //       |> option.map(to_expression)
  //       |> option.unwrap(e.NoCases)
  //     let matches =
  //       list.fold_right(matches, otherwise, fn(acc, match) {
  //         let #(label, value) = match
  //         let value = to_expression(value)
  //         e.Apply(e.Apply(e.Case(label), value), acc)
  //       })
  //     let top = to_expression(top)
  //     e.Apply(matches, top)
  //   }
  //   Vacant(comment) -> e.Vacant(comment)
  //   Integer(value) -> e.Integer(value)
  //   Binary(value) -> e.Binary(value)
  //   String(value) -> e.Str(value)

  //   Tag(label) -> e.Tag(label)
  //   Perform(label) -> e.Perform(label)
  //   Deep(label) -> e.Handle(label)
  //   Shallow(label) -> e.Shallow(label)
  //   Builtin(identifier) -> e.Builtin(identifier)
  // }
}

fn pattern_to_annotated(p, exp, rev) {
  case p {
    Bind(label) -> #(label, exp)
    Destructure(ds) -> {
      let exp =
        list.fold_right(ds, exp, fn(acc, d) {
          let #(label, var) = d
          #(
            a.Let(
              var,
              #(a.Apply(#(a.Select(label), rev), #(a.Variable("$"), rev)), rev),
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
    Variable(x) -> #(a.Variable(x), rev)
    Call(f, args) ->
      list.index_fold(args, to_annotated(f, [0, ..rev]), fn(acc, arg, i) {
        let arg = to_annotated(arg, [i + 1, ..rev])
        #(a.Apply(acc, arg), rev)
      })
    Function(args, body) -> {
      let len = list.length(args)
      let body = to_annotated(body, [len, ..rev])
      case args, body {
        [Bind("$")], #(a.Apply(inner, #(a.Variable("$"), _)), _) -> inner
        _, _ -> {
          let assert #(0, exp) =
            list.fold_right(args, #(len, body), fn(acc, arg) {
              let #(i, acc) = acc
              // start on body index
              let i = i - 1
              let #(var, body) = pattern_to_annotated(arg, acc, [i, ..rev])
              #(i, #(a.Lambda(var, body), rev))
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
              #(a.Let(var, to_annotated(value, [1, i, ..rev]), acc), [i, ..rev]),
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
        |> option.unwrap(#(a.Tail, [len, ..rev]))
      let assert #(0, exp) =
        list.fold_right(items, #(len, tail), fn(acc, item) {
          let #(i, acc) = acc
          let i = i - 1

          let item = to_annotated(item, [i, ..rev])
          #(i, #(a.Apply(#(a.Apply(#(a.Cons, rev), item), rev), acc), rev))
        })
      exp
    }
    Record(fields, rest) -> {
      let len = list.length(fields) * 2
      let #(build, rest) = case rest {
        None -> #(a.Extend, #(a.Empty, rev))
        Some(original) -> #(a.Overwrite, to_annotated(original, [len, ..rev]))
      }
      let assert #(0, exp) =
        list.fold_right(fields, #(len, rest), fn(acc, field) {
          let #(i, acc) = acc
          let i = i - 2
          let #(label, value) = field
          let value = to_annotated(value, [i + 1, ..rev])
          #(i, #(
            a.Apply(#(a.Apply(#(build(label), [i, ..rev]), value), rev), acc),
            rev,
          ))
        })
      exp
    }
    Select(from, label) -> {
      #(
        a.Apply(#(a.Select(label), [0, ..rev]), to_annotated(from, [1, ..rev])),
        rev,
      )
    }

    Case(top, matches, otherwise) -> {
      let len = list.length(matches)
      let otherwise = case otherwise {
        Some(otherwise) -> to_annotated(otherwise, [len + 1, ..rev])
        None -> #(a.NoCases, [len + 1, ..rev])
      }
      let assert #(1, matches) =
        list.fold_right(matches, #(len + 1, otherwise), fn(acc, match) {
          let #(i, acc) = acc
          let i = i - 1
          let #(label, branch) = match
          let branch = to_annotated(branch, [0, i, ..rev])
          let acc = #(
            a.Apply(#(a.Apply(#(a.Case(label), rev), branch), rev), acc),
            rev,
          )
          #(i, acc)
        })
      let top = to_annotated(top, [0, ..rev])

      let exp = a.Apply(matches, top)
      #(exp, rev)
    }
    Vacant(comment) -> #(a.Vacant(comment), rev)
    Integer(value) -> #(a.Integer(value), rev)
    Binary(value) -> #(a.Binary(value), rev)
    String(value) -> #(a.Str(value), rev)

    Tag(label) -> #(a.Tag(label), rev)
    Perform(label) -> #(a.Perform(label), rev)
    Deep(label) -> #(a.Handle(label), rev)
    Shallow(label) -> #(a.Shallow(label), rev)
    Builtin(identifier) -> #(a.Builtin(identifier), rev)
    Reference(identifier) -> #(a.Reference(identifier), rev)
  }
}
