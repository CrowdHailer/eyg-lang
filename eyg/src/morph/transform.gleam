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

fn do_split_around(items, left, acc) {
  case items, left {
    // pre is left reversed
    [item, ..after], 0 -> Ok(#(acc, item, after))
    [item, ..after], i -> do_split_around(after, i - i, [item, ..acc])
  }
}

pub fn focus_at(ast, path, acc) {
  case ast, path {
    exp, [] -> #(Exp(exp), acc)
    e.Block(assigns, then), [i, ..rest] -> {
      case i == list.length(assigns) {
        True -> focus_at(then, rest, [BlockTail(assigns), ..acc])
        False -> {
          let assert Ok(#(pre, #(x, value), post)) = split_around(assigns, i)
          case rest {
            [] -> #(Labeled(x, value, pre, post), acc)
            [0, ..rest] ->
              focus_at(value, rest, [BlockValue(x, pre, post, then), ..acc])
            _ -> panic
          }
        }
        _ -> panic
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
        _, _ -> panic
      }
    }
    e.Record(fields), [i, ..rest] -> {
      let assert Ok(#(pre, #(label, value), post)) = split_around(fields, i)
      case rest {
        [] -> #(Labeled(label, value, pre, post), acc)
        [0, ..rest] ->
          focus_at(value, rest, [RecordValue(label, pre, post), ..acc])
        _ -> panic
      }
    }
    _, _ -> todo
  }
}

// tricky because need to reutrn a type for fields etc
// fn child(exp,i) {
//   case exp {
//     e.Block(assigns, then) -> case int.compare(i, list.length(assigns)) {
//         order.Lt -> todo
//         order.Eq -> focus_at(then, rest, [BlockTail(assigns), ..acc])
//       }
//   }
//  }

pub type Zip =
  #(Focus, List(Break))

pub type Focus {
  Exp(e.Expression)
  LetAssign(
    label: String,
    value: e.Expression,
    pre: List(#(String, e.Expression)),
    post: List(#(String, e.Expression)),
    tail: e.Expression,
  )
  LetDestructureField(field: String, binding: String, pre: List(Nil))
  //   Does this need block pre and post?
  LetDestructureBinding(field: String)
  RecordField(
    label: String,
    value: e.Expression,
    pre: List(#(String, e.Expression)),
    post: List(#(String, e.Expression)),
  )
  Labeled(
    label: String,
    value: e.Expression,
    pre: List(#(String, e.Expression)),
    post: List(#(String, e.Expression)),
  )
}

// does Field and Field split have the same kind

pub type Break {
  BlockValue(
    var: String,
    pre: List(#(String, e.Expression)),
    post: List(#(String, e.Expression)),
    then: e.Expression,
  )
  BlockTail(assignments: List(#(String, e.Expression)))
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
  SelectValue
  OverwriteValue(
    label: String,
    pre: List(e.Expression),
    post: List(e.Expression),
  )
  OverwriteLabel(value: e.Expression)
  OverwriteTail
  CaseValue(label: String, pre: List(e.Expression), post: List(e.Expression))
  CaseLabel(value: e.Expression)
  CaseTail
}

// ok makes a lot of gc can pass 2 arg
pub fn step(zip) {
  let #(focus, zoom) = zip
  case zoom {
    [] -> Error(Nil)
    [break, ..rest] -> {
      // do_step(focus,break,rest) to unnest
      let exp = case focus {
        Exp(exp) -> unbreak(exp, break)
      }
      Ok(#(Exp(exp), rest))
    }
  }
}

fn unbreak(exp, break) {
  case break {
    BlockTail(assigments) -> e.Block(assigments, exp)
    CallFn(args) -> e.Call(exp, args)
    CallArg(f, pre, post) -> e.Call(f, list.flatten([pre, [exp], post]))
    ListItem(pre, post) -> e.List(list.flatten([pre, [exp], post]), None)
  }
}

fn call(zip) {
  let #(focus, zoom) = zip
  case focus {
    Exp(e) -> #(Exp(e.Vacant), [CallArg(e, [], []), ..zoom])
  }
}

// I think we can render by reversing the list potentially even starting on pre and post
fn line_above(zip) {
  case zip {
    #(Exp(tail), [BlockTail(lets), ..rest]) -> #(
      LetAssign("", e.Vacant, lets, [], tail),
      rest,
    )
    // If focus is on a block
    #(Exp(tail), []) -> #(LetAssign("", e.Vacant, [], [], tail), [])
    #(LetAssign(l, v, pre, post, tail), zoom) -> {
      let post = [#(l, v), ..post]
      #(LetAssign("", e.Vacant, pre, post, tail), zoom)
    }
    _ ->
      case step(zip) {
        Ok(zip) -> line_above(zip)
      }
  }
}

// line drag is possible then unwrap as an option
// how to highlight some scribble SVG's would be good

// can be done for call args etc
fn add_member(zip) {
  case zip {
    #(Exp(list), zoom) -> todo
    #(RecordField(label, value, pre, post), zoom) -> {
      let pre = list.append(pre, [#(label, value)])
      #(RecordField("", e.Vacant, pre, post), zoom)
    }
  }
}
// // defunctioning has been very useful for performance dont want recursive structure.
// // dont want to make rebuild fns when introspecting tree of how we got here.

// // TODO function to assign wherever
// // return and shift return for line above below

// fn drag_up(focus) {
//     case focus {
//         Assignment(_, [i,Block(lets,tail)]) ->
//         // list.length and up
//     }
//  }

//  fn spread_list(focus) {
//     case focus {
//         Expression(e.List())
//         Expression(_, [i,Block(lets,tail)]) ->
//         // list.length and up
//     }
//  }

//  fn insert_right() {
//     case focus {
//          ->
//     }
//   }
