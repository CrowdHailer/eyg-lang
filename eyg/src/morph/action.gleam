import gleam/io
import gleam/list
import morph/editable as e
import morph/transform as t

pub fn apply_key(k, zip) {
  case k {
    "ArrowUp" -> move_up(zip)
    "ArrowRight" -> move_right(zip)
    "ArrowLeft" -> move_left(zip)
    "a" -> increase(zip)
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
      #(t.Exp(last), [t.BlockValue(label, pre, [], then), ..rest])
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

fn call(zip) {
  case zip {
    #(t.Exp(f), [t.CallFn(args), ..rest]) -> {
      #(t.Exp(e.String("NEW")), [t.CallArg(f, [], args), ..rest])
    }
    #(t.Exp(f), rest) -> {
      #(t.Exp(e.String("NEW")), [t.CallArg(f, [], []), ..rest])
    }
  }
}
