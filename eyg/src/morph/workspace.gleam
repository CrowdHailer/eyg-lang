// TODO move
// atelier, space etc
// note keep mounts etc away from tree transformation
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import eygir/expression as e
import morph/transform

pub type Mode {
  Navigate(actions: transform.Act)
}

pub type WorkSpace {
  WorkSpace(mode: Mode)
}

// true resumption in solid by not even needing key bindings, hash resumpt

pub fn handle_keydown(space: WorkSpace, key) {
  case space.mode {
    Navigate(actions) ->
      case key {
        "q" -> todo("!!show code or deploy, prob behind command or automatic")
        "w" -> todo("call with")
        "e" -> todo("equal assignment")
        "r" -> todo("record")
        "t" -> todo("tuple now tag")
        "y" -> todo("copy")
        "u" -> todo("unwrap")
        "i" -> todo("insert test")
        "o" -> todo("o")
        "p" -> todo("provider not needed")
        // "a" -> transform.increase(actions)
        "s" -> todo("decrease")
        "d" -> todo("delete")
        "f" -> todo("function")
        "g" -> todo("get select")
        "h" -> todo("left")
        "j" -> todo("down")
        "k" -> todo("up")
        "l" -> todo("right")
        "z" -> todo("z")
        "x" -> todo("!!provider expansion not needed atm")
        "c" -> todo("call")
        "v" -> todo("variable")
        "b" -> todo("!binary")
        "n" -> todo("!named but this is likely to be tagged now")
        "m" -> todo("match")
        " " -> todo("space follow suggestion next error")
        _ -> space.mode
      }
  }
}

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

pub fn call_with(act: Act) {
  fn() { #([0, ..act.reversed], act.update(e.Apply(e.Vacant, act.target))) }
}

pub fn call(act: Act) {
  fn() { #([1, ..act.reversed], act.update(e.Apply(act.target, e.Vacant))) }
}

pub fn string(act: Act) {
  fn(value) { #(act.reversed, act.update(e.Binary(value))) }
}

pub fn function(act: Act) {
  fn(param) { #(act.reversed, act.update(e.Lambda(param, act.target))) }
}

pub fn assign(act: Act) {
  let exp = act.target
  case exp {
    e.Let(_, _, _) -> fn(label) {
      #([1, ..act.reversed], act.update(e.Let(label, e.Vacant, exp)))
    }
    exp -> fn(label) {
      #([2, ..act.reversed], act.update(e.Let(label, exp, e.Vacant)))
    }
  }
}

pub fn record(act: Act) {
  case act.target {
    e.Variable(from) -> e.Record([], Some(from))
    e.Vacant -> e.Record([], None)
    _ -> todo("should theese work")
  }
}

pub fn select(act: Act) {
  case act.target {
    e.Vacant -> fn(field) { act.update(e.Select(field)) }
    exp -> fn(field) { act.update(e.Apply(e.Select(field), exp)) }
  }
}

// Having everything be an expression dosn;t work for this if a branch has a function how do we know wich one to target
pub fn insert(act: Act) {
  case act.target {
    e.Let(label, value, then) ->
      Some(#(label, fn(label) { act.update(e.Let(label, value, then)) }))
    e.Lambda(param, body) ->
      Some(#(param, fn(param) { act.update(e.Lambda(param, body)) }))
    _ -> None
  }
}

// TODO up and down
// should we assume lets are tidy
// how does this work with an overflowed list
// tree to grid is hard so move is hard. could just use mouse
// z for zoom in just highlight all the letter press z again to move fast

// TODO be AWESOME if we can ui function stuff without a big string lookup

pub fn unwrap(act: Act) {
  case act.parent {
    Some(#(_, _, _, update)) -> Some(fn() { update(act.target) })
    None -> None
  }
}

// delete doesn't need to know parent type
pub fn delete(act: Act) {
  case act.target {
    e.Let(label, e.Vacant, then) -> fn() { #(act.reversed, act.update(then)) }
    e.Let(label, _, then) -> fn() {
      #(act.reversed, act.update(e.Let(label, e.Vacant, then)))
    }
    // TODO handle if parent is a row
    e.Vacant ->
      case act.parent {
        Some(#(index, reversed, exp, update)) ->
          // delete element
          case exp {
            // delete child function some none add index or not
            e.Record(fields, from) ->
              case list.length(fields) == index, from {
                True, Some(_) -> fn() {
                  #([index, ..reversed], update(e.Record(fields, None)))
                }
                True, None -> fn() { #(reversed, exp) }
                False, _ -> fn() {
                  let pre = list.take(fields, index)
                  let post = list.drop(fields, index + 1)
                  let fields = list.append(pre, post)
                  let reversed = [int.max(0, index - 1), ..reversed]
                  #(reversed, update(e.Record(fields, from)))
                }
              }
            // simply move up if nothing to remoce
            _ -> fn() { #(reversed, update(exp)) }
          }
        // if root and delete is an edge case we dont care about
        // update with target is wasted effort
        None -> fn() { #(act.reversed, act.update(act.target)) }
      }
    _ -> fn() { #(act.reversed, act.update(e.Vacant)) }
  }
}

// TODO up and down

pub fn copy(act: Act) {
  act.target
}
