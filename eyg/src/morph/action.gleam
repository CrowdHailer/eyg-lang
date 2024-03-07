import gleam/io
import gleam/list
import gleam/option.{None, Some}
import morph/editable as e
import morph/transform as t

// make morph transforms, does not include undo redo or types
// TODO clicking, eiter by full path or relative path
// inline block so bground is not full still needs to be on new line
pub type MaybeString {
  NeedString(fn(String) -> t.Zip)
  NoString(t.Zip)
}

pub fn apply_key(k, zip) {
  case k {
    "ArrowUp" -> move_up(zip)
    "ArrowDown" -> move_down(zip)
    "ArrowRight" -> move_right(zip)
    "ArrowLeft" -> move_left(zip)
    // TODO needs an enum for list or done
    "E" -> line_above(zip)
    // "e" -> to_var(zip)
    // "r" -> record(zip)
    // "t" -> tag(zip)
    "a" -> increase(zip)
    "s" -> decrease(zip)
    "d" -> delete(zip)
    // "f" -> function(zip)
    "l" -> list(zip)
    "c" -> call(zip)
    "m" -> match(zip)
    "M" -> open_match(zip)

    _ -> {
      io.debug(k)
      zip
    }
  }
}

pub fn move_up(zip) {
  case zip {
    #(t.Exp(then), [t.BlockTail(assigns), ..rest]) -> {
      let assert [#(pattern, last), ..pre] = list.reverse(assigns)
      #(t.Assign(t.AssignStatement(pattern), last, pre, [], then), rest)
    }
    #(
      t.Assign(t.AssignStatement(label), value, [#(l, v), ..pre], post, then),
      rest,
    ) -> #(
      t.Assign(t.AssignStatement(l), v, pre, [#(label, value), ..post], then),
      rest,
    )
    #(t.Match(top, label, branch, [new, ..pre], post, otherwise), rest) -> {
      #(
        t.Match(top, new.0, new.1, pre, [#(label, branch), ..post], otherwise),
        rest,
      )
    }
    #(t.Exp(otherwise), [t.CaseTail(top, [_, ..] as matches), ..rest]) -> {
      let assert [#(label, branch), ..pre] = list.reverse(matches)
      #(t.Match(top, label, branch, pre, [], Some(otherwise)), rest)
    }
    _ -> {
      io.debug(zip)
      case t.step(zip) {
        Ok(zip) -> move_up(zip)
      }
    }
  }
}

pub fn move_down(zip) {
  case zip {
    #(t.Assign(detail, value, pre, [new, ..post], then), rest) -> {
      let p = t.assigned_pattern(detail)
      let pre = [#(p, value), ..pre]

      #(t.Assign(t.AssignStatement(new.0), new.1, pre, post, then), rest)
    }
    #(t.Assign(detail, value, pre, [], then), rest) -> {
      let p = t.assigned_pattern(detail)
      let assigns = t.gather_around(pre, #(p, value), [])
      #(t.Exp(then), [t.BlockTail(assigns), ..rest])
    }
    #(t.Match(top, label, branch, pre, [new, ..post], otherwise), rest) -> {
      #(
        t.Match(top, new.0, new.1, [#(label, branch), ..pre], post, otherwise),
        rest,
      )
    }
    #(t.Match(top, label, branch, pre, [], Some(otherwise)), rest) -> {
      let matches = list.reverse([#(label, branch), ..pre])
      #(t.Exp(otherwise), [t.CaseTail(top, matches), ..rest])
    }

    _ -> {
      case t.step(zip) {
        Ok(zip) -> move_down(zip)
      }
    }
  }
}

pub fn move_right(zip) {
  case zip {
    #(t.Exp(f), [t.CallFn(args), ..rest]) -> {
      let assert [first, ..args] = args
      #(t.Exp(first), [t.CallArg(f, [], args), ..rest])
    }
    #(t.Exp(a), [t.CallArg(f, pre, [n, ..post]), ..rest]) -> {
      #(t.Exp(n), [t.CallArg(f, [a, ..pre], post), ..rest])
    }
    #(t.Assign(detail, value, pre, post, then), zoom) -> {
      let same = t.Assign(_, value, pre, post, then)
      case detail {
        t.AssignStatement(_) -> panic as "too high to move right"
        t.AssignPattern(pattern) -> #(t.Exp(value), [
          t.BlockValue(pattern, pre, post, then),
          ..zoom
        ])
        t.AssignField(label, var, pre, post) -> #(
          same(t.AssignBind(label, var, pre, post)),
          zoom,
        )
        t.AssignBind(label, var, pre, [#(l, v), ..post]) -> #(
          same(t.AssignField(l, v, [#(label, var), ..pre], post)),
          zoom,
        )
        t.AssignBind(label, var, pre_p, []) -> {
          let pattern = e.Destructure(t.gather_around(pre_p, #(label, var), []))
          #(t.Exp(value), [t.BlockValue(pattern, pre, post, then), ..zoom])
        }
      }
    }
    #(t.FnParam(t.AssignPattern(p), pre, [], body), rest) -> {
      let args = list.reverse([p, ..pre])
      #(t.Exp(body), [t.Body(args), ..rest])
    }
    #(t.FnParam(t.AssignPattern(p), pre, [next, ..post], body), rest) -> {
      #(t.FnParam(t.AssignPattern(next), [p, ..pre], post, body), rest)
    }
    #(t.FnParam(t.AssignField(l, x, pre_p, post_p), pre, post, body), rest) -> {
      #(t.FnParam(t.AssignBind(l, x, pre_p, post_p), pre, post, body), rest)
    }
    #(
      t.FnParam(
        t.AssignBind(l, x, pre_p, [#(l2, x2), ..post_p]),
        pre,
        post,
        body,
      ),
      rest,
    ) -> {
      #(
        t.FnParam(
          t.AssignField(l2, x2, [#(l, x), ..pre_p], post_p),
          pre,
          post,
          body,
        ),
        rest,
      )
    }
    // TODO movebind to right into body
    #(t.FnParam(t.AssignBind(l, x, pre_p, []), pre, [], body), rest) -> {
      let pattern = e.Destructure(t.gather_around(pre_p, #(l, x), []))
      #(t.Exp(body), [t.Body(t.gather_around(pre, pattern, [])), ..rest])
    }

    #(t.Exp(exp), [t.ListItem(pre, [next, ..post], tail), ..rest]) -> #(
      t.Exp(next),
      [t.ListItem([exp, ..pre], post, tail), ..rest],
    )
    #(t.Exp(exp), [t.ListItem(pre, [], Some(next)), ..rest]) -> #(t.Exp(next), [
      t.ListTail(list.reverse([exp, ..pre])),
      ..rest
    ])
    #(t.Label(l, v, pre, post, for), rest) -> {
      #(t.Exp(v), [t.RecordValue(l, pre, post, for), ..rest])
    }
    #(t.Exp(exp), [t.RecordValue(l, pre, [], t.Overwrite(new)), ..rest]) -> #(
      t.Exp(new),
      [t.OverwriteTail([#(l, exp), ..pre]), ..rest],
    )
    #(t.Exp(top), [t.CaseTop([#(label, branch), ..post], otherwise), ..rest]) -> {
      #(t.Match(top, label, branch, [], post, otherwise), rest)
    }
    #(t.Match(top, label, value, pre, post, otherwise), zoom) -> {
      let zoom = [t.CaseMatch(top, label, pre, post, otherwise), ..zoom]
      #(t.Exp(value), zoom)
    }
    _ -> {
      io.debug(#("cant move right", zip))
      zip
    }
  }
}

pub fn move_left(zip) {
  case zip {
    #(t.Exp(value), [t.BlockValue(pattern, pre, post, then), ..rest]) -> {
      let detail = case pattern {
        e.Bind(label) -> t.AssignPattern(pattern)
        e.Destructure(bindings) -> {
          let [#(label, var), ..pre] = list.reverse(bindings)
          t.AssignBind(label, var, pre, [])
        }
      }
      #(t.Assign(detail, value, pre, post, then), rest)
    }
    #(t.Assign(detail, value, pre, post, then), zoom) -> {
      let same = t.Assign(_, value, pre, post, then)
      case detail {
        t.AssignStatement(_) | t.AssignPattern(_) ->
          panic as "too high to move left"
        t.AssignBind(label, var, pre, post) -> #(
          same(t.AssignField(label, var, pre, post)),
          zoom,
        )
        t.AssignField(label, var, [#(l, v), ..pre], post) -> #(
          same(t.AssignBind(l, v, pre, [#(label, var), ..post])),
          zoom,
        )
      }
    }
    #(t.Exp(a), [t.CallArg(f, [], post), ..rest]) -> {
      #(t.Exp(f), [t.CallFn([a, ..post]), ..rest])
    }
    #(t.Exp(a), [t.CallArg(f, [n, ..pre], post), ..rest]) -> {
      #(t.Exp(n), [t.CallArg(f, pre, [a, ..post]), ..rest])
    }
    #(t.Exp(body), [t.Body(args), ..rest]) -> {
      let [last, ..pre] = list.reverse(args)
      #(t.FnParam(t.AssignPattern(last), pre, [], body), rest)
    }
    #(t.Exp(exp), [t.ListItem([next, ..pre], post, tail), ..rest]) -> #(
      t.Exp(next),
      [t.ListItem(pre, [exp, ..post], tail), ..rest],
    )
    #(t.Exp(exp), [t.ListTail(items), ..rest]) -> {
      let [next, ..pre] = list.reverse(items)
      #(t.Exp(next), [t.ListItem(pre, [], Some(exp)), ..rest])
    }
    #(t.Exp(exp), [t.RecordValue(l, pre, post, for), ..rest]) -> {
      #(t.Label(l, exp, pre, post, for), rest)
    }
    #(t.Exp(original), [t.OverwriteTail([#(l, next), ..pre]), ..rest]) -> {
      #(t.Exp(next), [t.RecordValue(l, pre, [], t.Overwrite(original)), ..rest])
    }
    #(t.Exp(branch), [t.CaseMatch(top, l, pre, post, otherwise), ..rest]) -> {
      #(t.Match(top, l, branch, pre, post, otherwise), rest)
    }
    #(t.FnParam(t.AssignPattern(p), [next, ..pre], post, body), rest) -> {
      #(t.FnParam(t.AssignPattern(next), pre, [p, ..post], body), rest)
    }
    #(t.FnParam(t.AssignBind(l, x, pre_p, post_p), pre, post, body), rest) -> #(
      t.FnParam(t.AssignField(l, x, pre_p, post_p), pre, post, body),
      rest,
    )
    #(
      t.FnParam(
        t.AssignField(l, x, [#(l2, x2), ..pre_p], post_p),
        pre,
        post,
        body,
      ),
      rest,
    ) -> #(
      t.FnParam(
        t.AssignBind(l2, x2, pre_p, [#(l, x), ..post_p]),
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
  let assert Ok(zip) = t.step(zip)
  zip
}

pub fn decrease(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Assign(detail, v, pre, post, then) -> {
      #(t.Assign(decrease_assign(detail), v, pre, post, then), zoom)
    }
    t.Exp(exp) -> t.focus_at(exp, [0], zoom)
    t.Labeled(l, v, pre, post, for) -> #(t.Label(l, v, pre, post, for), zoom)
    t.FnParam(detail, pre, post, body) -> #(
      t.FnParam(decrease_assign(detail), pre, post, body),
      zoom,
    )
    _ -> {
      io.debug(zip)
      panic as "decrease"
    }
  }
}

// for predicate
const vacant = e.Vacant

pub fn delete(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    t.Exp(e.Vacant), [t.ListItem(pre, [next, ..post], tail), ..zoom] -> {
      #(t.Exp(next), [t.ListItem(pre, post, tail), ..zoom])
    }
    t.Exp(e.Vacant), [t.CallArg(f, pre, [next, ..post]), ..zoom] -> {
      #(t.Exp(next), [t.CallArg(f, pre, post), ..zoom])
    }
    t.Exp(e.Vacant), [t.CallArg(f, [next, ..pre], []), ..zoom] -> {
      #(t.Exp(next), [t.CallArg(f, pre, []), ..zoom])
    }
    t.Exp(e.Vacant), [t.CallArg(f, [], []), ..zoom] -> {
      #(t.Exp(e.Call(f, [e.Vacant])), zoom)
    }

    t.Exp(x), _ if x != vacant -> #(t.Exp(e.Vacant), zoom)
    t.Assign(t.AssignStatement(_), _, pre, [#(pattern, value), ..post], then), zoom -> #(
      t.Assign(t.AssignStatement(pattern), value, pre, post, then),
      zoom,
    )
    t.Assign(t.AssignStatement(_), _, [#(pattern, value), ..pre], [], then), zoom -> #(
      t.Assign(t.AssignStatement(pattern), value, pre, [], then),
      zoom,
    )
    t.Assign(t.AssignStatement(_), _, [], [], then), zoom -> #(
      t.Exp(then),
      zoom,
    )
    t.FnParam(t.AssignPattern(_), pre, [pattern, ..post], body), _ -> #(
      t.FnParam(t.AssignPattern(pattern), pre, post, body),
      zoom,
    )
    t.FnParam(t.AssignPattern(_), [pattern, ..pre], [], body), _ -> #(
      t.FnParam(t.AssignPattern(pattern), pre, [], body),
      zoom,
    )
    t.FnParam(t.AssignField(_, _, pre_p, [#(l, x), ..post_p]), pre, post, body), _ -> #(
      t.FnParam(t.AssignField(l, x, pre_p, post_p), pre, post, body),
      zoom,
    )
    t.FnParam(t.AssignBind(_, _, pre_p, [#(l, x), ..post_p]), pre, post, body), _ -> #(
      t.FnParam(t.AssignBind(l, x, pre_p, post_p), pre, post, body),
      zoom,
    )
    t.FnParam(t.AssignField(_, _, [#(l, x), ..pre_p], []), pre, post, body), _ -> #(
      t.FnParam(t.AssignField(l, x, pre_p, []), pre, post, body),
      zoom,
    )
    t.FnParam(t.AssignBind(_, _, [#(l, x), ..pre_p], []), pre, post, body), _ -> #(
      t.FnParam(t.AssignBind(l, x, pre_p, []), pre, post, body),
      zoom,
    )
    t.Label(_, _, pre, [#(l, v), ..post], for), _ -> #(
      t.Label(l, v, pre, post, for),
      zoom,
    )
    t.Label(_, _, [#(l, v), ..pre], [], for), _ -> #(
      t.Label(l, v, pre, [], for),
      zoom,
    )

    t.Match(top, _, _, pre, [#(label, branch), ..post], otherwise), zoom -> #(
      t.Match(top, label, branch, pre, post, otherwise),
      zoom,
    )
    t.Match(top, _, _, [#(label, branch), ..pre], [], otherwise), zoom -> #(
      t.Match(top, label, branch, pre, [], otherwise),
      zoom,
    )

    // if no left/right then step
    _, _ -> {
      io.debug(zip)
      case t.step(zip) {
        Ok(zip) -> zip
        Error(Nil) -> zip
      }
    }
  }
  // t.Assign(t.AssignField(_l,_v, pre,[next,..post]),value,)
}

fn decrease_assign(detail) {
  case detail {
    t.AssignStatement(pattern) -> t.AssignPattern(pattern)
    t.AssignPattern(e.Destructure([#(label, var), ..rest])) ->
      t.AssignField(label, var, [], rest)
  }
}

pub fn assign(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    t.Exp(value), [t.BlockTail(assigns), ..zoom] -> fn(pattern) {
      let assigns = list.append(assigns, [#(pattern, value)])
      let zoom = [t.BlockTail(assigns), ..zoom]
      #(t.Exp(e.Vacant), zoom)
    }
    t.Exp(value), _ -> fn(pattern) {
      let zoom = [t.BlockTail([#(pattern, value)]), ..zoom]
      #(t.Exp(e.Vacant), zoom)
    }
  }
}

pub fn line_above(zip) {
  case zip {
    #(t.Exp(x), [t.ListItem(pre, post, tail), ..rest]) -> {
      #(t.Exp(e.Vacant), [t.ListItem(pre, [x, ..post], tail), ..rest])
    }
    #(t.Assign(t.AssignStatement(pattern), value, pre, post, then), rest) -> #(
      t.Assign(
        t.AssignStatement(e.Bind("")),
        e.Vacant,
        pre,
        [#(pattern, value), ..post],
        then,
      ),
      rest,
    )
    #(t.Exp(then), [t.BlockTail(lets), ..rest]) -> #(
      t.Assign(t.AssignStatement(e.Bind("")), e.Vacant, lets, [], then),
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

// always start from scratch
pub fn variable(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(_) -> fn(x) { #(t.Exp(e.Variable(x)), zoom) }
  }
}

// All functions curried so calling f on one should return existing function as argument
pub fn function(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(e.Function(args, body)) -> fn(new) {
      #(t.Exp(e.Function([e.Bind(new), ..args], body)), zoom)
    }
    t.Exp(body) -> fn(new) { #(t.Exp(e.Function([e.Bind(new)], body)), zoom) }
  }
}

pub fn call(zip) {
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

pub fn string(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(e.String(content)) -> #(content, fn(content) {
      #(t.Exp(e.String(content)), zoom)
    })
    t.Exp(_) -> #("", fn(content) { #(t.Exp(e.String(content)), zoom) })
  }
}

// This is create_list
pub fn list(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(e.Vacant) -> #(t.Exp(e.List([], None)), zoom)
    t.Exp(item) -> #(t.Exp(e.List([item], None)), zoom)
  }
}

pub fn extend_list(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    t.Exp(e.List(items, tail)), _ ->
      NoString(#(t.Exp(e.Vacant), [t.ListItem([], items, tail), ..zoom]))

    t.Exp(exp), [t.ListItem(pre, post, tail), ..rest] ->
      NoString(
        #(t.Exp(e.Vacant), [t.ListItem([exp, ..pre], post, tail), ..rest]),
      )
    t.Exp(e.Record(fields, original)), _ ->
      NeedString(fn(new) {
        let for = case original {
          Some(original) -> t.Overwrite(original)
          None -> t.Record
        }
        #(t.Exp(e.Vacant), [t.RecordValue(new, [], fields, for), ..zoom])
      })
    t.FnParam(t.AssignPattern(e.Destructure(fields)), pre, post, body), _ ->
      NeedString(fn(new) {
        #(t.FnParam(t.AssignBind(new, new, [], fields), pre, post, body), zoom)
      })
    _, _ -> NoString(zip)
  }
}

pub fn spread_list(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    t.Exp(e.List(items, None)), _ -> #(t.Exp(e.Vacant), [
      t.ListTail(items),
      ..zoom
    ])

    t.Exp(exp), [t.ListItem(pre, [], None), ..rest] -> #(t.Exp(e.Vacant), [
      t.ListTail(list.reverse([exp, ..pre])),
      ..rest
    ])
  }
}

pub fn record(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(e.Vacant) -> NoString(#(t.Exp(e.Record([], None)), zoom))
    t.Exp(e.Record([], None)) ->
      NeedString(fn(new) { #(t.Exp(e.Record([#(new, e.Vacant)], None)), zoom) })
    t.Exp(item) ->
      NeedString(fn(new) { #(t.Exp(e.Record([#(new, item)], None)), zoom) })
    t.Assign(detail, value, pre, post, then) -> {
      let detail = case detail {
        t.AssignPattern(e.Bind(var)) -> t.AssignField(var, var, [], [])
        t.AssignPattern(e.Destructure(fields)) ->
          t.AssignField("f", "f", list.reverse(fields), [])
      }
      NoString(#(t.Assign(detail, value, pre, post, then), zoom))
    }
    t.FnParam(t.AssignPattern(e.Bind(label)), pre, post, body) ->
      NoString(#(
        t.FnParam(
          t.AssignPattern(e.Destructure([#(label, label)])),
          pre,
          post,
          body,
        ),
        zoom,
      ))
    t.Labeled(l, v, pre, post, for) ->
      NeedString(fn(new) {
        #(t.Labeled(new, e.Vacant, [#(l, v), ..pre], post, for), zoom)
      })
  }
}

pub fn overwrite(zip) {
  let #(focus, zoom) = zip
  io.debug(focus)
  case focus {
    t.Exp(e.Vacant) | t.Exp(e.Record([], None)) -> fn(new) {
      #(t.Exp(e.Vacant), [
        t.RecordValue(new, [], [], t.Overwrite(e.Vacant)),
        ..zoom
      ])
    }
    t.Exp(e.Record(fields, None)) -> fn(new) {
      #(t.Exp(e.Vacant), [t.OverwriteTail(list.reverse(fields)), ..zoom])
    }
    t.Exp(item) -> fn(new) {
      #(t.Exp(e.Vacant), [t.RecordValue(new, [], [], t.Overwrite(item)), ..zoom])
    }
  }
}

pub fn tag(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(e.Vacant) -> fn(new) { #(t.Exp(e.Tag(new)), zoom) }
    t.Exp(inner) -> fn(new) {
      #(t.Exp(e.Tag(new)), [t.CallFn([inner]), ..zoom])
    }
  }
}

pub fn match(zip) {
  let #(focus, zoom) = zip
  let new = e.Function([e.Bind("_")], e.Vacant)
  let focus = case focus {
    t.Exp(exp) -> t.Match(exp, "Ok", new, [], [], None)
    t.Match(top, label, branch, pre, post, otherwise) -> {
      let post = [#(label, branch), ..post]
      t.Match(top, "New", new, pre, post, otherwise)
    }
  }
  #(focus, zoom)
}

pub fn open_match(zip) {
  let #(focus, zoom) = zip
  let new = e.Function([e.Bind("_")], e.Vacant)
  case focus {
    t.Exp(e.Case(top, matches, None)) -> #(t.Exp(new), [
      t.CaseTail(top, matches),
      ..zoom
    ])
    t.Match(top, label, branch, pre, post, otherwise) -> {
      let matches = t.gather_around(pre, #(label, branch), post)
      #(t.Exp(new), [t.CaseTail(top, matches), ..zoom])
    }
  }
}

pub fn perform(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(e.Vacant) -> fn(new) { #(t.Exp(e.Perform(new)), zoom) }
    t.Exp(inner) -> fn(new) {
      #(t.Exp(e.Perform(new)), [t.CallFn([inner]), ..zoom])
    }
  }
}

pub fn builtin(zip) {
  let #(focus, zoom) = zip
  case focus {
    t.Exp(e.Builtin(content)) -> #(content, fn(content) {
      #(t.Exp(e.Builtin(content)), zoom)
    })
    t.Exp(_) -> #("", fn(content) { #(t.Exp(e.Builtin(content)), zoom) })
  }
}
