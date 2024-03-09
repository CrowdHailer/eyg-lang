import gleam/io
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/result.{try}
import morph/editable as e
import morph/projection as p

pub fn move_up(zip) {
  case zip {
    #(p.Exp(then), [p.BlockTail(assigns), ..rest]) -> {
      let assert [#(pattern, last), ..pre] = list.reverse(assigns)
      Ok(#(p.Assign(p.AssignStatement(pattern), last, pre, [], then), rest))
    }
    #(
      p.Assign(p.AssignStatement(label), value, [#(l, v), ..pre], post, then),
      rest,
    ) ->
      Ok(#(
        p.Assign(p.AssignStatement(l), v, pre, [#(label, value), ..post], then),
        rest,
      ))
    #(p.Match(top, label, branch, [new, ..pre], post, otherwise), rest) -> {
      Ok(#(
        p.Match(top, new.0, new.1, pre, [#(label, branch), ..post], otherwise),
        rest,
      ))
    }
    #(p.Exp(otherwise), [p.CaseTail(top, [_, ..] as matches), ..rest]) -> {
      // TODO revese in CaseTail
      let assert [#(label, branch), ..pre] = list.reverse(matches)
      Ok(#(p.Match(top, label, branch, pre, [], Some(otherwise)), rest))
    }
    _ -> {
      use zip <- try(p.step(zip))
      move_up(zip)
    }
  }
}

pub fn move_down(zip) {
  case zip {
    #(p.Assign(detail, value, pre, [new, ..post], then), rest) -> {
      let p = p.assigned_pattern(detail)
      let pre = [#(p, value), ..pre]

      Ok(#(p.Assign(p.AssignStatement(new.0), new.1, pre, post, then), rest))
    }
    #(p.Assign(detail, value, pre, [], then), rest) -> {
      let p = p.assigned_pattern(detail)
      let assigns = listx.gather_around(pre, #(p, value), [])
      Ok(#(p.Exp(then), [p.BlockTail(assigns), ..rest]))
    }
    #(p.Match(top, label, branch, pre, [new, ..post], otherwise), rest) -> {
      Ok(#(
        p.Match(top, new.0, new.1, [#(label, branch), ..pre], post, otherwise),
        rest,
      ))
    }
    #(p.Match(top, label, branch, pre, [], Some(otherwise)), rest) -> {
      let matches = list.reverse([#(label, branch), ..pre])
      Ok(#(p.Exp(otherwise), [p.CaseTail(top, matches), ..rest]))
    }
    _ -> {
      use zip <- try(p.step(zip))
      move_down(zip)
    }
  }
}

pub fn move_right(zip) {
  case zip {
    #(p.Exp(f), [p.CallFn(args), ..rest]) -> {
      let assert [first, ..args] = args
      #(p.Exp(first), [p.CallArg(f, [], args), ..rest])
    }
    #(p.Exp(a), [p.CallArg(f, pre, [n, ..post]), ..rest]) -> {
      #(p.Exp(n), [p.CallArg(f, [a, ..pre], post), ..rest])
    }
    #(p.Assign(detail, value, pre, post, then), zoom) -> {
      let same = p.Assign(_, value, pre, post, then)
      case detail {
        p.AssignStatement(_) -> panic as "too high to move right"
        p.AssignPattern(pattern) -> #(p.Exp(value), [
          p.BlockValue(pattern, pre, post, then),
          ..zoom
        ])
        p.AssignField(label, var, pre, post) -> #(
          same(p.AssignBind(label, var, pre, post)),
          zoom,
        )
        p.AssignBind(label, var, pre, [#(l, v), ..post]) -> #(
          same(p.AssignField(l, v, [#(label, var), ..pre], post)),
          zoom,
        )
        p.AssignBind(label, var, pre_p, []) -> {
          let pattern =
            e.Destructure(listx.gather_around(pre_p, #(label, var), []))
          #(p.Exp(value), [p.BlockValue(pattern, pre, post, then), ..zoom])
        }
      }
    }
    #(p.FnParam(p.AssignPattern(p), pre, [], body), rest) -> {
      let args = list.reverse([p, ..pre])
      #(p.Exp(body), [p.Body(args), ..rest])
    }
    #(p.FnParam(p.AssignPattern(p), pre, [next, ..post], body), rest) -> {
      #(p.FnParam(p.AssignPattern(next), [p, ..pre], post, body), rest)
    }
    #(p.FnParam(p.AssignField(l, x, pre_p, post_p), pre, post, body), rest) -> {
      #(p.FnParam(p.AssignBind(l, x, pre_p, post_p), pre, post, body), rest)
    }
    #(
      p.FnParam(
        p.AssignBind(l, x, pre_p, [#(l2, x2), ..post_p]),
        pre,
        post,
        body,
      ),
      rest,
    ) -> {
      #(
        p.FnParam(
          p.AssignField(l2, x2, [#(l, x), ..pre_p], post_p),
          pre,
          post,
          body,
        ),
        rest,
      )
    }
    // TODO movebind to right into body
    #(p.FnParam(p.AssignBind(l, x, pre_p, []), pre, [], body), rest) -> {
      let pattern = e.Destructure(listx.gather_around(pre_p, #(l, x), []))
      #(p.Exp(body), [p.Body(listx.gather_around(pre, pattern, [])), ..rest])
    }

    #(p.Exp(exp), [p.ListItem(pre, [next, ..post], tail), ..rest]) -> #(
      p.Exp(next),
      [p.ListItem([exp, ..pre], post, tail), ..rest],
    )
    #(p.Exp(exp), [p.ListItem(pre, [], Some(next)), ..rest]) -> #(p.Exp(next), [
      p.ListTail(list.reverse([exp, ..pre])),
      ..rest
    ])
    #(p.Label(l, v, pre, post, for), rest) -> {
      #(p.Exp(v), [p.RecordValue(l, pre, post, for), ..rest])
    }
    #(p.Exp(exp), [p.RecordValue(l, pre, [], p.Overwrite(new)), ..rest]) -> #(
      p.Exp(new),
      [p.OverwriteTail([#(l, exp), ..pre]), ..rest],
    )
    #(p.Exp(top), [p.CaseTop([#(label, branch), ..post], otherwise), ..rest]) -> {
      #(p.Match(top, label, branch, [], post, otherwise), rest)
    }
    #(p.Match(top, label, value, pre, post, otherwise), zoom) -> {
      let zoom = [p.CaseMatch(top, label, pre, post, otherwise), ..zoom]
      #(p.Exp(value), zoom)
    }
    _ -> {
      io.debug(#("cant move right", zip))
      zip
    }
  }
}

pub fn move_left(zip) {
  case zip {
    #(p.Exp(value), [p.BlockValue(pattern, pre, post, then), ..rest]) -> {
      let detail = case pattern {
        e.Bind(_label) -> p.AssignPattern(pattern)
        e.Destructure(bindings) -> {
          let [#(label, var), ..pre] = list.reverse(bindings)
          p.AssignBind(label, var, pre, [])
        }
      }
      #(p.Assign(detail, value, pre, post, then), rest)
    }
    #(p.Assign(detail, value, pre, post, then), zoom) -> {
      let same = p.Assign(_, value, pre, post, then)
      case detail {
        p.AssignStatement(_) | p.AssignPattern(_) ->
          panic as "too high to move left"
        p.AssignBind(label, var, pre, post) -> #(
          same(p.AssignField(label, var, pre, post)),
          zoom,
        )
        p.AssignField(label, var, [#(l, v), ..pre], post) -> #(
          same(p.AssignBind(l, v, pre, [#(label, var), ..post])),
          zoom,
        )
      }
    }
    #(p.Exp(a), [p.CallArg(f, [], post), ..rest]) -> {
      #(p.Exp(f), [p.CallFn([a, ..post]), ..rest])
    }
    #(p.Exp(a), [p.CallArg(f, [n, ..pre], post), ..rest]) -> {
      #(p.Exp(n), [p.CallArg(f, pre, [a, ..post]), ..rest])
    }
    #(p.Exp(body), [p.Body(args), ..rest]) -> {
      let [last, ..pre] = list.reverse(args)
      #(p.FnParam(p.AssignPattern(last), pre, [], body), rest)
    }
    #(p.Exp(exp), [p.ListItem([next, ..pre], post, tail), ..rest]) -> #(
      p.Exp(next),
      [p.ListItem(pre, [exp, ..post], tail), ..rest],
    )
    #(p.Exp(exp), [p.ListTail(items), ..rest]) -> {
      let [next, ..pre] = list.reverse(items)
      #(p.Exp(next), [p.ListItem(pre, [], Some(exp)), ..rest])
    }
    #(p.Exp(exp), [p.RecordValue(l, pre, post, for), ..rest]) -> {
      #(p.Label(l, exp, pre, post, for), rest)
    }
    #(p.Exp(original), [p.OverwriteTail([#(l, next), ..pre]), ..rest]) -> {
      #(p.Exp(next), [p.RecordValue(l, pre, [], p.Overwrite(original)), ..rest])
    }
    #(p.Exp(branch), [p.CaseMatch(top, l, pre, post, otherwise), ..rest]) -> {
      #(p.Match(top, l, branch, pre, post, otherwise), rest)
    }
    #(p.FnParam(p.AssignPattern(p), [next, ..pre], post, body), rest) -> {
      #(p.FnParam(p.AssignPattern(next), pre, [p, ..post], body), rest)
    }
    #(p.FnParam(p.AssignBind(l, x, pre_p, post_p), pre, post, body), rest) -> #(
      p.FnParam(p.AssignField(l, x, pre_p, post_p), pre, post, body),
      rest,
    )
    #(
      p.FnParam(
        p.AssignField(l, x, [#(l2, x2), ..pre_p], post_p),
        pre,
        post,
        body,
      ),
      rest,
    ) -> #(
      p.FnParam(
        p.AssignBind(l2, x2, pre_p, [#(l, x), ..post_p]),
        pre,
        post,
        body,
      ),
      rest,
    )
    _ -> {
      io.debug(#("cant move left", zip))
      zip
    }
  }
}

pub fn increase(zip) {
  let assert Ok(zip) = p.step(zip)
  zip
}

pub fn decrease(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Assign(detail, v, pre, post, then) -> {
      #(p.Assign(decrease_assign(detail), v, pre, post, then), zoom)
    }
    p.Exp(exp) -> p.focus_at(exp, [0], zoom)
    p.Labeled(l, v, pre, post, for) -> #(p.Label(l, v, pre, post, for), zoom)
    p.FnParam(detail, pre, post, body) -> #(
      p.FnParam(decrease_assign(detail), pre, post, body),
      zoom,
    )
    _ -> {
      io.debug(zip)
      panic as "decrease"
    }
  }
}

fn decrease_assign(detail) {
  case detail {
    p.AssignStatement(pattern) -> p.AssignPattern(pattern)
    p.AssignPattern(e.Destructure([#(label, var), ..rest])) ->
      p.AssignField(label, var, [], rest)
  }
}
