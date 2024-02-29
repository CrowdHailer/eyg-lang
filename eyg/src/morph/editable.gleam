import gleam/option.{type Option, None, Some}
import gleam/list
import eygir/annotated as a

pub type Pattern {
  Bind(String)
  Destructure(List(#(String, String)))
}

pub type Expression {
  // TODO block becomes pattern
  Variable(String)
  Block(List(#(String, Expression)), Expression)
  Call(Expression, List(Expression))
  List(List(Expression), Option(Expression))
  Record(List(#(String, Expression)))
  Overwrite(List(#(String, Expression)), String)
  Function(List(Pattern), Expression)
  Vacant
  Integer(Int)
  Binary
  String(String)
}

// Dont want block wrap for every expression
// pub type Block {
// }

pub fn from_annotated(node) {
  let #(exp, meta) = node
  case exp {
    a.Lambda(x, body) -> {
      let #(pattern, rest) = gather_destructure(body, x, [])
      gather_arguments(rest, [pattern])
    }
    a.Let(x, value, then) -> {
      let value = from_annotated(value)
      gather_assignments(then, [#(x, value)])
    }
    a.Apply(#(a.Apply(#(a.Extend(l), _), value), _), rest) ->
      gather_extends(rest, [#(l, from_annotated(value))])
    a.Empty -> Record([])

    a.Apply(#(a.Apply(#(a.Case(l), _), branch), _), otherwise) -> todo
  }
}

fn gather_arguments(node, acc) {
  let #(exp, meta) = node
  case exp {
    a.Lambda(x, body) -> {
      let #(pattern, rest) = gather_destructure(body, x, [])
      gather_arguments(rest, [pattern, ..acc])
    }
    _ -> todo
  }
}

//   case bindings {
//     [] -> #(Bind(x),body)
//     _ -> {
//         // todo check free vars in gather
//         #()
//     }
//   }
fn gather_destructure(node, var, acc) {
  let #(exp, meta) = node
  case exp {
    a.Let(x, #(a.Apply(#(a.Select(l), _), #(a.Variable(v), _)), _), then) if v == var ->
      gather_destructure(then, var, [#(l, x), ..acc])
    _ -> #(list.reverse(acc), node)
  }
}

fn gather_extends(node, acc) {
  let #(exp, meta) = node
  case exp {
    a.Apply(#(a.Apply(#(a.Extend(l), _), value), _), rest) ->
      gather_extends(rest, [#(l, from_annotated(value)), ..acc])
    a.Empty -> Record(list.reverse(acc))
  }
}

fn gather_assignments(node, acc) {
  let #(exp, meta) = node
  case exp {
    a.Let(x, value, then) ->
      gather_assignments(then, [#(x, from_annotated(value)), ..acc])
    _ -> {
      let assert Block([], expression) = from_annotated(node)
      Block(list.reverse(acc), expression)
    }
  }
}
