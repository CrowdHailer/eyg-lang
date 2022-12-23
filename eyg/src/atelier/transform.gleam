// TODO maybe morph
import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import eygir/expression as e

pub type Act {
  Act(
    target: e.Expression,
    update: fn(e.Expression) -> e.Expression,
    parent: Option(
      #(Int, List(Int), e.Expression, fn(e.Expression) -> e.Expression),
    ),
    reversed: List(Int),
  )
}

fn step(exp, i) {
  case exp, i {
    e.Lambda(param, body), 0 -> Ok(#(body, e.Lambda(param, _)))
    e.Apply(func, arg), 0 -> Ok(#(func, e.Apply(_, arg)))
    e.Apply(func, arg), 1 -> Ok(#(arg, e.Apply(func, _)))
    e.Let(label, value, then), 0 -> Ok(#(value, e.Let(label, _, then)))
    e.Let(label, value, then), 1 -> Ok(#(then, e.Let(label, value, _)))
    _, _ -> Error("invalid path")
  }
}

fn do_prepare(exp, selection, acc, update) {
  assert [i, ..rest] = selection
  try #(child, update_child) = step(exp, i)
  let update_child = fn(new) { update(update_child(new)) }
  case rest {
    [] ->
      Ok(Act(
        target: child,
        update: update_child,
        parent: Some(#(i, [], exp, update)),
        reversed: acc,
      ))
    _ -> do_prepare(child, rest, [i, ..acc], update_child)
  }
}

pub fn prepare(exp, selection) {
  let zip = fn(new) { new }
  case selection {
    [] -> Ok(Act(target: exp, update: zip, parent: None, reversed: []))
    _ -> do_prepare(exp, selection, [], zip)
  }
}
