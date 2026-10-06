//// Lower query rules to pure closures over a snapshot of the database.
//// Generated names contain `$`, which cannot occur in source identifiers.

import eyg/ir/tree as ir
import gleam/int
import gleam/list
import gleam/result.{try}

pub type Node =
  ir.Node(#(Int, Int))

type Step {
  Bind(String, Node)
  Test(Node)
}

pub fn call(op, args, span) {
  list.fold(args, #(ir.Query(op), span), fn(f, a) { #(ir.Apply(f, a), span) })
}

pub fn rule(head: Node, body: List(Node), variables: List(String), span) {
  use head <- try(case head {
    #(ir.Apply(#(ir.Tag(label), _), payload), _) ->
      Ok(call(ir.Fact(label), [payload], head.1))
    _ -> Error(#("a rule head must be Relation(value)", head.1.0))
  })
  use body <- try(clauses(body, head, variables, [], 0, span))
  Ok(call(ir.Rule, [#(ir.Lambda("$db", body), span)], span))
}

fn safe(node: Node, variables, bound) {
  case
    list.find(ir.free_variables(node, bound), fn(v) {
      list.contains(variables, v)
    })
  {
    Ok(v) -> Error(#("unbound query variable: " <> v, node.1.0))
    Error(Nil) -> Ok(Nil)
  }
}

fn clauses(body, head, variables, bound, index, span) {
  case body {
    [] -> {
      use _ <- try(safe(head, variables, bound))
      Ok(head)
    }
    [#(ir.Apply(#(ir.Tag(label), _), pattern), at), ..rest]
      if label != "True" && label != "False"
    -> {
      let row = "$row" <> int.to_string(index)
      let acc = "$acc" <> int.to_string(index)
      use #(bound, steps) <- try(
        pattern_steps(pattern, #(ir.Variable(row), at), variables, bound, []),
      )
      use next <- try(clauses(rest, head, variables, bound, index + 1, span))
      let next =
        list.fold(steps, next, fn(next, step) {
          case step {
            Bind(name, value) -> #(ir.Let(name, value, next), at)
            Test(condition) -> guard(condition, next, at)
          }
        })
      let merge = call(ir.Merge, [#(ir.Variable(acc), at), next], at)
      let fold = #(ir.Lambda(row, #(ir.Lambda(acc, merge), at)), at)
      let rows = call(ir.Resolve(label), [#(ir.Variable("$db"), at)], at)
      Ok(apply(
        #(ir.Builtin("list_fold"), at),
        [rows, call(ir.EmptyTable, [], at), fold],
        span,
      ))
    }
    [predicate, ..rest] -> {
      use _ <- try(safe(predicate, variables, bound))
      use next <- try(clauses(rest, head, variables, bound, index + 1, span))
      Ok(guard(predicate, next, predicate.1))
    }
  }
}

fn pattern_steps(pattern, value, variables, bound, steps) {
  case pattern {
    #(ir.Variable(name), _) ->
      case list.contains(variables, name) && !list.contains(bound, name) {
        True -> Ok(#([name, ..bound], [Bind(name, value), ..steps]))
        False -> equality(pattern, value, variables, bound, steps)
      }
    #(ir.Apply(#(ir.Apply(#(ir.Extend(field), _), inner), _), tail), at) -> {
      let selected = #(ir.Apply(#(ir.Select(field), at), value), at)
      use #(bound, steps) <- try(pattern_steps(
        inner,
        selected,
        variables,
        bound,
        steps,
      ))
      case tail {
        #(ir.Empty, _) -> Ok(#(bound, steps))
        _ -> pattern_steps(tail, value, variables, bound, steps)
      }
    }
    _ -> equality(pattern, value, variables, bound, steps)
  }
}

fn equality(pattern, value, variables, bound, steps) {
  use _ <- try(safe(pattern, variables, bound))
  let condition =
    apply(#(ir.Builtin("equal"), pattern.1), [pattern, value], pattern.1)
  Ok(#(bound, [Test(condition), ..steps]))
}

fn apply(f, args, span) {
  list.fold(args, f, fn(f, arg) { #(ir.Apply(f, arg), span) })
}

fn guard(condition, then, span) {
  let yes = #(ir.Lambda("$unit", then), span)
  let no = #(ir.Lambda("$unit", call(ir.EmptyTable, [], span)), span)
  let otherwise =
    apply(#(ir.Case("False"), span), [no, #(ir.NoCases, span)], span)
  apply(#(ir.Case("True"), span), [yes, otherwise, condition], span)
}
