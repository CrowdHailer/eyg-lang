//// Lower query rules to pure closures over a snapshot of the database.
//// Each relation clause becomes a `Match` whose key holds the fields already
//// known when the clause is reached, so a runtime can find rows with an index.
//// Generated names contain `$`, which cannot occur in source identifiers.

import eyg/ir/tree as ir
import gleam/int
import gleam/list
import gleam/result.{try}
import gleam/string

pub type Node =
  ir.Node(#(Int, Int))

type Step {
  Bind(String, Node)
  Test(Node)
  // Continue only when the value is the variant, binding its payload.
  Unwrap(label: String, value: Node, name: String)
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
  use body <- try(clauses(body, head, variables, [], 0))
  Ok(call(ir.Rule, [#(ir.Lambda("$db", body), span)], span))
}

fn unbound(node: Node, variables, bound) {
  list.find(ir.free_variables(node, bound), fn(v) {
    list.contains(variables, v)
  })
}

fn safe(node: Node, variables, bound) {
  case unbound(node, variables, bound) {
    Ok(v) -> Error(#("unbound query variable: " <> v, node.1.0))
    Error(Nil) -> Ok(Nil)
  }
}

fn clauses(body, head, variables, bound, index) {
  case body {
    [] -> {
      use _ <- try(safe(head, variables, bound))
      Ok(head)
    }
    [#(ir.Apply(#(ir.Tag(label), _), pattern), at), ..rest]
      if label != "True" && label != "False"
    -> {
      let row = "$row" <> int.to_string(index)
      // `{}` alone is a closed record to compare, not a pattern with no fields.
      let #(keys, pattern) = case pattern {
        #(ir.Empty, _) -> #([], pattern)
        _ -> split_keys(pattern, variables, bound)
      }
      use #(bound, steps) <- try(case keys, pattern {
        [_, ..], #(ir.Empty, _) -> Ok(#(bound, []))
        _, _ ->
          pattern_steps(pattern, #(ir.Variable(row), at), variables, bound, [])
      })
      use next <- try(clauses(rest, head, variables, bound, index + 1))
      let next = list.fold(steps, next, fn(next, step) { wrap(step, next, at) })
      let keys = list.sort(keys, fn(a, b) { string.compare(a.0, b.0) })
      let key =
        list.fold_right(keys, #(ir.Empty, at), fn(rest, field) {
          apply(#(ir.Extend(field.0), at), [field.1, rest], at)
        })
      let match = ir.Match(label, list.map(keys, fn(field) { field.0 }))
      Ok(call(
        match,
        [#(ir.Variable("$db"), at), key, #(ir.Lambda(row, next), at)],
        at,
      ))
    }
    [predicate, ..rest] -> {
      use _ <- try(safe(predicate, variables, bound))
      use next <- try(clauses(rest, head, variables, bound, index + 1))
      Ok(guard(predicate, next, predicate.1))
    }
  }
}

// Top level fields known before the clause runs become the key of the match.
// The remaining pattern still binds, unwraps and compares the other fields.
fn split_keys(pattern, variables, bound) {
  case pattern {
    #(ir.Apply(#(ir.Apply(#(ir.Extend(field), _), inner), _), tail), at) -> {
      let #(keys, tail) = split_keys(tail, variables, bound)
      case unbound(inner, variables, bound) {
        Error(Nil) -> #([#(field, inner), ..keys], tail)
        Ok(_) -> #(keys, apply(#(ir.Extend(field), at), [inner, tail], at))
      }
    }
    _ -> #([], pattern)
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
    #(ir.Apply(#(ir.Tag(label), _), inner), at) ->
      case unbound(inner, variables, bound) {
        Ok(_) -> {
          let name = "$" <> label <> int.to_string(at.0)
          let steps = [Unwrap(label, value, name), ..steps]
          let payload = #(ir.Variable(name), at)
          pattern_steps(inner, payload, variables, bound, steps)
        }
        Error(Nil) -> equality(pattern, value, variables, bound, steps)
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

fn wrap(step, next, at) {
  case step {
    Bind(name, value) -> #(ir.Let(name, value, next), at)
    Test(condition) -> guard(condition, next, at)
    Unwrap(label, value, name) -> {
      let otherwise = #(ir.Lambda("$other", call(ir.EmptyTable, [], at)), at)
      apply(
        #(ir.Case(label), at),
        [#(ir.Lambda(name, next), at), otherwise, value],
        at,
      )
    }
  }
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
