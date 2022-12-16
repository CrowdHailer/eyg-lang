import gleam/list
import gleam/option.{None, Option, Some}
import eygir/expression as e

pub type Act {
  Act(
    path: List(Int),
    // path is different to all the belo
    up: Option(List(Int)),
    down: Option(List(Int)),
    left: Bool,
    right: Bool,
    above: Option(fn(String) -> e.Expression),
    map: Option(fn(fn(e.Expression) -> e.Expression) -> e.Expression),
    unwrap: Option(fn() -> e.Expression),
    delete: Option(fn() -> e.Expression),
  )
}

// delete

fn step(exp, i) {
  case exp, i {
    e.Apply(func, arg), 0 -> #(func, e.Apply(_, arg))
    e.Apply(func, arg), 1 -> #(func, e.Apply(func, _))
    e.Let(label, value, then), 1 -> #(value, e.Let(label, _, then))
    e.Let(label, value, then), 2 -> #(then, e.Let(label, value, _))
  }
}

// check paths together
fn check_right(act, exp, i) {
  let right = case exp, i {
    e.Apply(_, _), 0 -> True
    exp, _ -> False
  }
  Act(..act, right: right)
}

fn do_delete(act, exp, k) {
  case exp {
    e.Vacant -> act
    e.Let(label, _, then) -> {
      let new = e.Let(label, e.Vacant, then)
      Act(..act, delete: Some(fn() { k(new) }))
    }
    _ -> Act(..act, delete: Some(fn() { k(e.Vacant) }))
  }
}

fn do_unwrap(act, child, k) {
  Act(..act, unwrap: Some(fn() { k(child) }))
}

fn space_above(act, exp, index, build) {
  case exp, index {
    e.Let(label, value, then), 2 -> {
      let above = Some(fn(new) { build(e.Let(new, e.Vacant, exp)) })
      Act(..act, above: above)
    }
    e.Let(label, value, then), _ -> {
      let above =
        Some(fn(new) { build(e.Let(label, value, e.Let(new, e.Vacant, then))) })
      Act(..act, above: above)
    }
    _, _ -> act
  }
  // TODO very root needs top above creation
}

fn space_below(act, exp, index, build_inner) {
  case exp, index {
    e.Let(label, value, then), i if i < 2 -> {
      let below =
        Some(fn(new) { e.Let(label, value, e.Let(new, e.Vacant, then)) })
      // TODO write in extending act
      Act(..act)
    }
  }
}

fn do_left(exp, i, k) {
  case exp, i {
    e.Apply(func, arg), 1 -> k(e.Apply(arg, func))
  }
}

pub fn do_prepare(act, path, exp, build_outer) {
  case path {
    [] -> {
      let act =
        Act(
          ..act,
          above: case act.above {
            Some(x) -> Some(x)
            None -> Some(e.Let(_, e.Vacant, exp))
          },
          down: case exp {
            // TODO real path
            e.Let(_, _, _) -> Some([2, 2])
            _ -> act.down
          },
          map: Some(case exp {
            e.Let(label, old, then) -> fn(update) {
              build_outer(e.Let(label, update(old), then))
            }
            old -> fn(update) { update(old) }
          }),
        )
      Ok(act)
    }

    [index, ..rest] -> {
      // delete always and merge
      let #(child, build_inner) = step(exp, index)
      act
      |> check_right(exp, index)
      |> space_above(child, index, build_inner)
      |> do_delete(child, build_inner)
      // Note nothing clever just passes to outer
      |> do_unwrap(child, build_outer)
      |> do_prepare(rest, child, build_inner)
    }
  }
  //   Escape cancel the temp state
  // Enter commit the temp

  // increase/decrease
}

// Next is already ok in the path

// can have rename in the match clause needs index, or a big ui to change them all
// root actions always succeeds

// edit hits binary

pub fn prepare(path, exp) {
  let act =
    Act(
      path: path,
      up: None,
      down: None,
      left: False,
      right: False,
      above: None,
      map: None,
      unwrap: None,
      delete: None,
    )
  do_prepare(act, path, exp, fn(e) { e })
}

pub fn up(act: Act) {
  // TODO this is increase not up
  case act.path {
    [] -> None
    p -> Some(list.take(p, list.length(p) - 1))
  }
}

pub fn down(act: Act) {
  act.down
}

pub fn left(act) {
  None
}

pub fn right(act: Act) {
  case act.right {
    True -> {
      // inside because need case of path being empty list
      let pre = list.take(act.path, list.length(act.path) - 1)
      assert Ok(last) = list.at(act.path, list.length(act.path) - 1)
      Some(list.append(pre, [last + 1]))
    }
    False -> None
  }
}

pub fn increase(act: Act) {
  case act.path {
    [] -> None
    p -> Some(list.take(p, list.length(p) - 1))
  }
}

pub fn line_above(act: Act) {
  act.above
}

pub fn variable(act: Act) {
  case act.map {
    Some(r) -> Some(fn(label) { r(fn(_) { e.Variable(label) }) })
    None -> None
  }
}

pub fn function(act: Act) {
  case act.map {
    Some(r) -> Some(fn(label) { r(e.Lambda(label, _)) })
    None -> None
  }
}

pub fn call(act: Act) {
  case act.map {
    Some(r) -> Some(fn() { r(e.Apply(_, e.Vacant)) })
    None -> None
  }
}

pub fn call_with(act: Act) {
  case act.map {
    Some(r) -> Some(fn() { r(e.Apply(e.Vacant, _)) })
    None -> None
  }
}

pub fn assign(act: Act) {
  case act.map {
    Some(r) -> Some(fn(label) { r(e.Let(label, _, e.Vacant)) })
    None -> None
  }
}

pub fn string(act: Act) {
  case act.map {
    Some(r) -> Some(fn(value) { r(fn(_) { e.Binary(value) }) })
    None -> None
  }
}

pub fn select(act: Act) {
  // TODO map so tag without call if already Vacant spot
  case act.map {
    Some(r) -> Some(fn(label) { r(e.Apply(e.Select(label), _)) })
    None -> None
  }
  // case e.Vacant {
  //   e.Vacant -> fn(label) { kont(e.Select(label)) }
  //   term -> fn(label) { kont(e.Apply(e.Select(label), term)) }
  // }
}

pub fn tag(act: Act) {
  // TODO map so tag without call if already Vacant spot
  case act.map {
    Some(r) -> Some(fn(label) { r(e.Apply(e.Tag(label), _)) })
    None -> None
  }
}

pub fn perform(act: Act) {
  // TODO map so tag without call if already Vacant spot
  case act.map {
    Some(r) -> Some(fn(label) { r(e.Apply(e.Perform(label), _)) })
    None -> None
  }
}

// pub fn insert(exp: e.Expression) -> Nil {
//   case exp {
//     e.Let(l, v, t) -> {
//       let resume = fn(label) { kont(e.Let(label, v, t)) }
//     }
//   }
// }

pub fn delete(act: Act) {
  act.delete
}

pub fn unwrap(act: Act) {
  act.unwrap
}
