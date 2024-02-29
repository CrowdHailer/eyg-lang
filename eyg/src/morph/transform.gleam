import gleam/list
import morph/editable as e

// from Embed drop for morph/notepad
// inference, loading, running, undo, redo, no mapping from text to position, no pallet
// or have everything in a command pallet and selection options, return continue fn and maybe label
// really focus on transforms to make it worthwhile

// block is interesting because how do yo address key or value I guess another kind of zipper
// Type checking is not part of this if we make it fast
// how do we link paths in is harder

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
}

pub type Break {
  BlockValue
  BlockTail(assignments: List(#(String, e.Expression)))
  CallFn(args: List(e.Expression))
  CallArg(func: e.Expression, pre: List(e.Expression), post: List(e.Expression))
  Body(args: List(e.Pattern))
  ListItem(pre: List(e.Expression), post: List(e.Expression))
  ListTail
  RecordValue(label: String, pre: List(e.Expression), post: List(e.Expression))
  RecordLabel(value: e.Expression)
  SelectValue
  SelectLabel
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
fn step(zip) {
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
