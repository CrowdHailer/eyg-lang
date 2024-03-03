import gleam/io
import gleam/option.{None, Some}
import gleam/order
import gleam/int
import gleam/list
import morph/editable as e

// from Embed drop for morph/notepad
// inference, loading, running, undo, redo, no mapping from text to position, no pallet
// or have everything in a command pallet and selection options, return continue fn and maybe label
// really focus on transforms to make it worthwhile

// block is interesting because how do yo address key or value I guess another kind of zipper
// Type checking is not part of this if we make it fast
// how do we link paths in is harder

// press i starts insert mode
// how do I render the tree, meta or from tree

// split_around can have then as 0 see func args so that you can match on beginning of list or empty for tail
// can have a field focus with a type for bulding but maybe easier to stay concrete
// TODO test focus to expression type one big tree is nice
// TODO unzip must get to the same tree
// TODO add height to multi so we can know when to stop

// NO type inference addition

// Need to print focus on no expression values

// if empty we error but all my blocks must have a value, not true for lit
fn split_around(items, at) {
  do_split_around(items, at, [])
}

// TODO  Make a split type to reuse pre/post/value

fn do_split_around(items, left, acc) {
  case items, left {
    // pre is left reversed
    [item, ..after], 0 -> Ok(#(acc, item, after))
    [item, ..after], i -> do_split_around(after, i - 1, [item, ..acc])
  }
}

fn move(a, b) {
  case a {
    [] -> b
    [i, ..a] -> move(a, [i, ..b])
  }
}

pub fn gather_around(pre, item, post) {
  move(pre, [item, ..post])
}

pub fn focus_at(ast, path, acc) {
  case ast, path {
    exp, [] -> #(Exp(exp), acc)
    e.Block(assigns, then), [i, ..rest] -> {
      case i == list.length(assigns) {
        True -> focus_at(then, rest, [BlockTail(assigns), ..acc])
        False -> {
          let assert Ok(#(pre, #(pattern, value), post)) =
            split_around(assigns, i)
          case rest {
            [] -> #(
              Assign(AssignStatement(pattern), value, pre, post, then),
              acc,
            )
            [0] -> #(
              Assign(AssignPattern(pattern), value, pre, post, then),
              acc,
            )
            [0, i] -> {
              case pattern {
                e.Destructure(fields) -> {
                  let detail = {
                    let assert Ok(#(pre, #(label, var), post)) =
                      split_around(fields, i / 2)

                    case i % 2 {
                      0 -> AssignField(label, var, pre, post)
                      1 -> AssignBind(label, var, pre, post)
                    }
                  }
                  #(Assign(detail, value, pre, post, then), acc)
                }
              }
            }
            [1, ..rest] ->
              focus_at(value, rest, [
                BlockValue(pattern, pre, post, then),
                ..acc
              ])
            _ -> panic as "bad sub in block"
          }
        }
      }
    }
    e.Function(params, body), [i, ..rest] -> {
      case i == list.length(params) {
        True -> focus_at(body, rest, [Body(params), ..acc])
        False -> {
          let Ok(#(pre, p, post)) = split_around(params, i)
          case rest {
            [] -> {
              #(FnParam(p, pre, post, body), acc)
            }
          }
        }
      }
    }
    e.Call(func, args), [0, ..rest] ->
      focus_at(func, rest, [CallFn(args), ..acc])
    e.Call(func, args), [i, ..rest] -> {
      let assert Ok(#(pre, value, post)) = split_around(args, i - 1)
      focus_at(value, rest, [CallArg(func, pre, post), ..acc])
    }
    e.List(items, tail), [i, ..rest] -> {
      case i == list.length(items), tail {
        True, Some(tail) -> focus_at(tail, rest, [ListTail(items), ..acc])
        False, _ -> {
          let assert Ok(#(pre, value, post)) = split_around(items, i)
          focus_at(value, rest, [ListItem(pre, post), ..acc])
        }
        _, _ -> panic as "bad list"
      }
    }
    e.Record(fields), [i, ..rest] -> {
      let assert Ok(#(pre, #(label, value), post)) = split_around(fields, i)
      case rest {
        [] -> #(Labeled(label, value, pre, post), acc)
        [0] -> #(Label(label, value, pre, post, Record), acc)
        [1, ..rest] ->
          focus_at(value, rest, [RecordValue(label, pre, post), ..acc])
        _ -> panic as "record focus"
      }
    }
    _, _ -> {
      io.debug(#(ast, path))
      todo as "foxus_At"
    }
  }
}

pub type Zip =
  #(Focus, List(Break))

pub type AssignFocus {
  AssignStatement(e.Pattern)
  AssignPattern(e.Pattern)
  AssignField(
    field: String,
    var: String,
    pre: List(#(String, String)),
    post: List(#(String, String)),
  )
  AssignBind(
    field: String,
    var: String,
    pre: List(#(String, String)),
    post: List(#(String, String)),
  )
}

pub type Focus {
  Exp(e.Expression)
  Assign(
    focus: AssignFocus,
    value: e.Expression,
    pre: List(#(e.Pattern, e.Expression)),
    post: List(#(e.Pattern, e.Expression)),
    tail: e.Expression,
  )
  FnParam(
    pattern: e.Pattern,
    pre: List(e.Pattern),
    post: List(e.Pattern),
    body: e.Expression,
  )
  Labeled(
    label: String,
    value: e.Expression,
    pre: List(#(String, e.Expression)),
    post: List(#(String, e.Expression)),
  )
  Label(
    label: String,
    value: e.Expression,
    pre: List(#(String, e.Expression)),
    post: List(#(String, e.Expression)),
    for: WithLabel,
  )
}

pub type WithLabel {
  Record
}

// scope is a bad name due to variable scope
// lens?
pub fn text(scope) {
  let #(focus, zoom) = scope
  case focus {
    Exp(e.String(value)) ->
      Ok(#(value, fn(new) { #(Exp(e.String(new)), zoom) }))
    Assign(detail, value, pre, post, then) -> {
      let assert Ok(#(content, build)) = case detail {
        AssignStatement(_) -> Error(Nil)
        AssignPattern(e.Bind(var)) ->
          Ok(#(var, fn(new) { AssignPattern(e.Bind(var)) }))
        AssignField(label, var, pre, post) ->
          Ok(#(label, fn(new) { AssignField(new, var, pre, post) }))
        AssignBind(label, var, pre, post) ->
          Ok(#(var, fn(new) { AssignBind(label, new, pre, post) }))
      }
      Ok(
        #(content, fn(new) {
          #(Assign(build(new), value, pre, post, then), zoom)
        }),
      )
    }
  }
}

// does Field and Field split have the same kind

pub type Break {
  BlockValue(
    pattern: e.Pattern,
    pre: List(#(e.Pattern, e.Expression)),
    post: List(#(e.Pattern, e.Expression)),
    then: e.Expression,
  )
  BlockTail(assignments: List(#(e.Pattern, e.Expression)))
  CallFn(args: List(e.Expression))
  CallArg(func: e.Expression, pre: List(e.Expression), post: List(e.Expression))
  Body(args: List(e.Pattern))
  ListItem(pre: List(e.Expression), post: List(e.Expression))
  ListTail(items: List(e.Expression))
  RecordValue(
    label: String,
    pre: List(#(String, e.Expression)),
    post: List(#(String, e.Expression)),
  )
  // SelectValue
  // OverwriteValue(
  //   label: String,
  //   pre: List(e.Expression),
  //   post: List(e.Expression),
  // )
  // OverwriteLabel(value: e.Expression)
  // OverwriteTail
  // CaseValue(label: String, pre: List(e.Expression), post: List(e.Expression))
  // CaseLabel(value: e.Expression)
  // CaseTail
}

// ok makes a lot of gc can pass 2 arg
pub fn step(zip) {
  let #(focus, zoom) = zip
  case focus {
    Exp(exp) ->
      case zoom {
        [] -> Error(Nil)
        [break, ..rest] -> {
          case break {
            BlockValue(p, pre, post, then) ->
              Ok(#(Assign(AssignStatement(p), exp, pre, post, then), rest))
            _ -> Ok(#(Exp(unbreak(exp, break)), rest))
          }
        }
      }
    Assign(AssignStatement(pattern), value, pre, post, then) ->
      Ok(#(
        Exp(e.Block(gather_around(pre, #(pattern, value), post), then)),
        zoom,
      ))
    FnParam(p, pre, post, body) ->
      Ok(#(Exp(e.Function(gather_around(pre, p, post), body)), zoom))
    // TODO use for
    Label(l, value, pre, post, _for) ->
      Ok(#(Labeled(l, value, pre, post), zoom))
    Labeled(l, value, pre, post) ->
      Ok(#(Exp(e.Record(gather_around(pre, #(l, value), post))), zoom))
    _ -> {
      io.debug(focus)
      panic as "when stepping"
    }
  }
}

fn unbreak(exp, break) {
  case break {
    BlockTail(assigments) -> e.Block(assigments, exp)
    BlockValue(var, pre, post, then) ->
      e.Block(gather_around(pre, #(var, exp), post), then)
    CallFn(args) -> e.Call(exp, args)
    CallArg(f, pre, post) -> e.Call(f, list.flatten([pre, [exp], post]))
    Body(args) -> e.Function(args, exp)
    ListItem(pre, post) -> e.List(gather_around(pre, exp, post), None)
    ListTail(items) -> e.List(items, Some(exp))
    RecordValue(label, pre, post) ->
      e.Record(gather_around(pre, #(label, exp), post))
  }
}
