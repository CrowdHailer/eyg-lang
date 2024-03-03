import gleam/io
import gleam/list
import gleam/option.{None}
import morph/editable as e
import morph/transform as t

// make morph transforms, does not include undo redo or types
// TODO insert mode
// clicking, eiter by full path or relative path
// inline block so bground is not full still needs to be on new line
pub fn apply_key(k, zip) {
  case k {
    "ArrowUp" -> move_up(zip)
    "ArrowRight" -> move_right(zip)
    "ArrowLeft" -> move_left(zip)
    "E" -> line_above(zip)
    "e" -> to_var(zip)
    "r" -> record(zip)
    "a" -> increase(zip)
    "s" -> decrease(zip)
    "f" -> function(zip)
    "l" -> list(zip)
    "c" -> call(zip)

    _ -> {
      io.debug(k)
      zip
    }
  }
}

fn move_up(zip) {
  case zip {
    #(t.Exp(then), [t.BlockTail(assigns), ..rest]) -> {
      let assert [#(label, last), ..pre] = list.reverse(assigns)
      #(t.LetAssign(label, last, pre, [], then), rest)
      // #(t.Exp(last), [t.BlockValue(label, pre, [], then), ..rest])
    }
    #(t.LetAssign(label, value, [#(l, v), ..pre], post, then), rest) -> #(
      t.LetAssign(l, v, pre, [#(label, value), ..post], then),
      rest,
    )
    _ -> {
      io.debug(zip)
      case t.step(zip) {
        Ok(zip) -> move_up(zip)
      }
    }
  }
}

fn move_right(zip) {
  io.debug(zip)
  case zip {
    #(t.Exp(f), [t.CallFn(args), ..rest]) -> {
      let assert [first, ..args] = args
      #(t.Exp(first), [t.CallArg(f, [], args), ..rest])
    }
    #(t.Exp(a), [t.CallArg(f, pre, [n, ..post]), ..rest]) -> {
      #(t.Exp(n), [t.CallArg(f, [a, ..pre], post), ..rest])
    }
    #(t.FnParam(p, pre, [], body), rest) -> {
      let args = list.reverse([p, ..pre])
      #(t.Exp(body), [t.Body(args), ..rest])
    }
  }
}

fn move_left(zip) {
  io.debug(zip)
  case zip {
    #(t.Exp(a), [t.CallArg(f, [], post), ..rest]) -> {
      #(t.Exp(f), [t.CallFn([a, ..post]), ..rest])
    }
    #(t.Exp(a), [t.CallArg(f, [n, ..pre], post), ..rest]) -> {
      #(t.Exp(n), [t.CallArg(f, pre, [a, ..post]), ..rest])
    }
  }
}

fn increase(zip) {
  let assert Ok(zip) = t.step(zip)
  zip
}

fn decrease(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.LetAssign(l, v, pre, post, then) -> {
      #(t.Exp(v), [t.BlockValue(l, pre, post, then), ..zoom])
    }
    t.Exp(exp) -> t.focus_at(exp, [0], zoom)
    t.Labeled(l, v, pre, post) -> #(t.Label(l, v, pre, post, t.Record), zoom)
    _ -> {
      io.debug(zip)
      panic as "decrease"
    }
  }
}

fn to_var(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(value) -> #(t.LetAssign(e.Bind(""), value, [], [], e.Vacant), zoom)
  }
}

fn line_above(zip) {
  case zip {
    #(t.Exp(x), [t.ListItem(pre, post), ..rest]) -> {
      #(t.Exp(e.Vacant), [t.ListItem(pre, [x, ..post]), ..rest])
    }
    #(t.LetAssign(label, value, pre, post, then), rest) -> #(
      t.LetAssign(e.Bind(""), e.Vacant, pre, [#(label, value), ..post], then),
      rest,
    )
    #(t.Exp(then), [t.BlockTail(lets), ..rest]) -> #(
      t.LetAssign(e.Bind(""), e.Vacant, lets, [], then),
      rest,
    )
    _ -> {
      io.debug(zip)
      case t.step(zip) {
        Ok(zip) -> line_above(zip)
      }
    }
  }
}

fn function(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(body) -> #(t.Exp(e.Function([e.Bind("xyz")], body)), zoom)
  }
}

fn call(zip) {
  case zip {
    #(t.Exp(e.Call(f, args)), rest) -> {
      #(t.Exp(e.Vacant), [t.CallArg(f, list.reverse(args), []), ..rest])
    }
    #(t.Exp(f), [t.CallFn(args), ..rest]) -> {
      #(t.Exp(e.Vacant), [t.CallArg(f, [], args), ..rest])
    }
    #(t.Exp(f), rest) -> {
      #(t.Exp(e.Vacant), [t.CallArg(f, [], []), ..rest])
    }
  }
}

fn list(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(e.Vacant) -> #(t.Exp(e.List([], None)), zoom)
    t.Exp(item) -> #(t.Exp(e.List([item], None)), zoom)
  }
}

fn record(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(e.Vacant) -> #(t.Exp(e.Record([])), zoom)
    t.Exp(e.Record([])) -> #(t.Exp(e.Record([#("", e.Vacant)])), zoom)
    t.Exp(item) -> #(t.Exp(e.Record([#("field", item)])), zoom)
    t.Labeled(l, v, pre, post) -> #(
      t.Labeled("new", e.Vacant, [#(l, v), ..pre], post),
      zoom,
    )
  }
}
