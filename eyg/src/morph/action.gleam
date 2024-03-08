import gleam/io
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import morph/editable as e
import morph/projection as p

// make morph transforms, does not include undo redo or types
// TODO clicking, eiter by full path or relative path
// inline block so bground is not full still needs to be on new line
pub type MaybeString {
  NeedString(fn(String) -> p.Projection)
  NoString(p.Projection)
}

pub fn move_up(zip) {
  case zip {
    #(p.Exp(then), [p.BlockTail(assigns), ..rest]) -> {
      let assert [#(pattern, last), ..pre] = list.reverse(assigns)
      #(p.Assign(p.AssignStatement(pattern), last, pre, [], then), rest)
    }
    #(
      p.Assign(p.AssignStatement(label), value, [#(l, v), ..pre], post, then),
      rest,
    ) -> #(
      p.Assign(p.AssignStatement(l), v, pre, [#(label, value), ..post], then),
      rest,
    )
    #(p.Match(top, label, branch, [new, ..pre], post, otherwise), rest) -> {
      #(
        p.Match(top, new.0, new.1, pre, [#(label, branch), ..post], otherwise),
        rest,
      )
    }
    #(p.Exp(otherwise), [p.CaseTail(top, [_, ..] as matches), ..rest]) -> {
      let assert [#(label, branch), ..pre] = list.reverse(matches)
      #(p.Match(top, label, branch, pre, [], Some(otherwise)), rest)
    }
    _ -> {
      io.debug(zip)
      case p.step(zip) {
        Ok(zip) -> move_up(zip)
      }
    }
  }
}

pub fn move_down(zip) {
  case zip {
    #(p.Assign(detail, value, pre, [new, ..post], then), rest) -> {
      let p = p.assigned_pattern(detail)
      let pre = [#(p, value), ..pre]

      #(p.Assign(p.AssignStatement(new.0), new.1, pre, post, then), rest)
    }
    #(p.Assign(detail, value, pre, [], then), rest) -> {
      let p = p.assigned_pattern(detail)
      let assigns = listx.gather_around(pre, #(p, value), [])
      #(p.Exp(then), [p.BlockTail(assigns), ..rest])
    }
    #(p.Match(top, label, branch, pre, [new, ..post], otherwise), rest) -> {
      #(
        p.Match(top, new.0, new.1, [#(label, branch), ..pre], post, otherwise),
        rest,
      )
    }
    #(p.Match(top, label, branch, pre, [], Some(otherwise)), rest) -> {
      let matches = list.reverse([#(label, branch), ..pre])
      #(p.Exp(otherwise), [p.CaseTail(top, matches), ..rest])
    }

    _ -> {
      case p.step(zip) {
        Ok(zip) -> move_down(zip)
      }
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
        e.Bind(label) -> p.AssignPattern(pattern)
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

// for predicate
const vacant = e.Vacant

pub fn delete(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    p.Exp(e.Vacant), [p.ListItem(pre, [next, ..post], tail), ..zoom] -> {
      #(p.Exp(next), [p.ListItem(pre, post, tail), ..zoom])
    }
    p.Exp(e.Vacant), [p.CallArg(f, pre, [next, ..post]), ..zoom] -> {
      #(p.Exp(next), [p.CallArg(f, pre, post), ..zoom])
    }
    p.Exp(e.Vacant), [p.CallArg(f, [next, ..pre], []), ..zoom] -> {
      #(p.Exp(next), [p.CallArg(f, pre, []), ..zoom])
    }
    p.Exp(e.Vacant), [p.CallArg(f, [], []), ..zoom] -> {
      #(p.Exp(e.Call(f, [e.Vacant])), zoom)
    }

    p.Exp(x), _ if x != vacant -> #(p.Exp(e.Vacant), zoom)
    p.Assign(p.AssignStatement(_), _, pre, [#(pattern, value), ..post], then), zoom -> #(
      p.Assign(p.AssignStatement(pattern), value, pre, post, then),
      zoom,
    )
    p.Assign(p.AssignStatement(_), _, [#(pattern, value), ..pre], [], then), zoom -> #(
      p.Assign(p.AssignStatement(pattern), value, pre, [], then),
      zoom,
    )
    p.Assign(p.AssignStatement(_), _, [], [], then), zoom -> #(
      p.Exp(then),
      zoom,
    )
    p.FnParam(p.AssignPattern(_), pre, [pattern, ..post], body), _ -> #(
      p.FnParam(p.AssignPattern(pattern), pre, post, body),
      zoom,
    )
    p.FnParam(p.AssignPattern(_), [pattern, ..pre], [], body), _ -> #(
      p.FnParam(p.AssignPattern(pattern), pre, [], body),
      zoom,
    )
    p.FnParam(p.AssignField(_, _, pre_p, [#(l, x), ..post_p]), pre, post, body), _ -> #(
      p.FnParam(p.AssignField(l, x, pre_p, post_p), pre, post, body),
      zoom,
    )
    p.FnParam(p.AssignBind(_, _, pre_p, [#(l, x), ..post_p]), pre, post, body), _ -> #(
      p.FnParam(p.AssignBind(l, x, pre_p, post_p), pre, post, body),
      zoom,
    )
    p.FnParam(p.AssignField(_, _, [#(l, x), ..pre_p], []), pre, post, body), _ -> #(
      p.FnParam(p.AssignField(l, x, pre_p, []), pre, post, body),
      zoom,
    )
    p.FnParam(p.AssignBind(_, _, [#(l, x), ..pre_p], []), pre, post, body), _ -> #(
      p.FnParam(p.AssignBind(l, x, pre_p, []), pre, post, body),
      zoom,
    )
    p.Label(_, _, pre, [#(l, v), ..post], for), _ -> #(
      p.Label(l, v, pre, post, for),
      zoom,
    )
    p.Label(_, _, [#(l, v), ..pre], [], for), _ -> #(
      p.Label(l, v, pre, [], for),
      zoom,
    )

    p.Match(top, _, _, pre, [#(label, branch), ..post], otherwise), zoom -> #(
      p.Match(top, label, branch, pre, post, otherwise),
      zoom,
    )
    p.Match(top, _, _, [#(label, branch), ..pre], [], otherwise), zoom -> #(
      p.Match(top, label, branch, pre, [], otherwise),
      zoom,
    )

    // if no left/right then step
    _, _ -> {
      io.debug(zip)
      case p.step(zip) {
        Ok(zip) -> zip
        Error(Nil) -> zip
      }
    }
  }
  // p.Assign(p.AssignField(_l,_v, pre,[next,..post]),value,)
}

fn decrease_assign(detail) {
  case detail {
    p.AssignStatement(pattern) -> p.AssignPattern(pattern)
    p.AssignPattern(e.Destructure([#(label, var), ..rest])) ->
      p.AssignField(label, var, [], rest)
  }
}

pub fn assign(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    p.Exp(value), [p.BlockTail(assigns), ..zoom] -> fn(pattern) {
      let assigns = list.append(assigns, [#(pattern, value)])
      let zoom = [p.BlockTail(assigns), ..zoom]
      #(p.Exp(e.Vacant), zoom)
    }
    p.Exp(value), _ -> fn(pattern) {
      let zoom = [p.BlockTail([#(pattern, value)]), ..zoom]
      #(p.Exp(e.Vacant), zoom)
    }
  }
}

pub fn line_above(zip) {
  case zip {
    #(p.Exp(x), [p.ListItem(pre, post, tail), ..rest]) -> {
      #(p.Exp(e.Vacant), [p.ListItem(pre, [x, ..post], tail), ..rest])
    }
    #(p.Assign(p.AssignStatement(pattern), value, pre, post, then), rest) -> #(
      p.Assign(
        p.AssignStatement(e.Bind("")),
        e.Vacant,
        pre,
        [#(pattern, value), ..post],
        then,
      ),
      rest,
    )
    #(p.Exp(then), [p.BlockTail(lets), ..rest]) -> #(
      p.Assign(p.AssignStatement(e.Bind("")), e.Vacant, lets, [], then),
      rest,
    )
    _ -> {
      io.debug(zip)
      case p.step(zip) {
        Ok(zip) -> line_above(zip)
      }
    }
  }
}

// always start from scratch
pub fn variable(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(_) -> fn(x) { #(p.Exp(e.Variable(x)), zoom) }
  }
}

// All functions curried so calling f on one should return existing function as argument
pub fn function(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Function(args, body)) -> fn(new) {
      #(p.Exp(e.Function([e.Bind(new), ..args], body)), zoom)
    }
    p.Exp(body) -> fn(new) { #(p.Exp(e.Function([e.Bind(new)], body)), zoom) }
  }
}

pub fn call(zip) {
  case zip {
    #(p.Exp(e.Call(f, args)), rest) -> {
      #(p.Exp(e.Vacant), [p.CallArg(f, list.reverse(args), []), ..rest])
    }
    #(p.Exp(f), [p.CallFn(args), ..rest]) -> {
      #(p.Exp(e.Vacant), [p.CallArg(f, [], args), ..rest])
    }
    #(p.Exp(f), rest) -> {
      #(p.Exp(e.Vacant), [p.CallArg(f, [], []), ..rest])
    }
  }
}

pub fn string(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.String(content)) -> #(content, fn(content) {
      #(p.Exp(e.String(content)), zoom)
    })
    p.Exp(_) -> #("", fn(content) { #(p.Exp(e.String(content)), zoom) })
  }
}

// This is create_list
pub fn list(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Vacant) -> #(p.Exp(e.List([], None)), zoom)
    p.Exp(item) -> #(p.Exp(e.List([item], None)), zoom)
  }
}

pub fn extend_list(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    p.Exp(e.List(items, tail)), _ ->
      NoString(#(p.Exp(e.Vacant), [p.ListItem([], items, tail), ..zoom]))

    p.Exp(exp), [p.ListItem(pre, post, tail), ..rest] ->
      NoString(
        #(p.Exp(e.Vacant), [p.ListItem([exp, ..pre], post, tail), ..rest]),
      )
    p.Exp(e.Record(fields, original)), _ ->
      NeedString(fn(new) {
        let for = case original {
          Some(original) -> p.Overwrite(original)
          None -> p.Record
        }
        #(p.Exp(e.Vacant), [p.RecordValue(new, [], fields, for), ..zoom])
      })
    p.FnParam(p.AssignPattern(e.Destructure(fields)), pre, post, body), _ ->
      NeedString(fn(new) {
        #(p.FnParam(p.AssignBind(new, new, [], fields), pre, post, body), zoom)
      })
    _, _ -> NoString(zip)
  }
}

pub fn spread_list(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    p.Exp(e.List(items, None)), _ -> #(p.Exp(e.Vacant), [
      p.ListTail(items),
      ..zoom
    ])

    p.Exp(exp), [p.ListItem(pre, [], None), ..rest] -> #(p.Exp(e.Vacant), [
      p.ListTail(list.reverse([exp, ..pre])),
      ..rest
    ])
  }
}

pub fn record(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Vacant) -> NoString(#(p.Exp(e.Record([], None)), zoom))
    p.Exp(e.Record([], None)) ->
      NeedString(fn(new) { #(p.Exp(e.Record([#(new, e.Vacant)], None)), zoom) })
    p.Exp(item) ->
      NeedString(fn(new) { #(p.Exp(e.Record([#(new, item)], None)), zoom) })
    p.Assign(detail, value, pre, post, then) -> {
      let detail = case detail {
        p.AssignPattern(e.Bind(var)) -> p.AssignField(var, var, [], [])
        p.AssignPattern(e.Destructure(fields)) ->
          p.AssignField("f", "f", list.reverse(fields), [])
      }
      NoString(#(p.Assign(detail, value, pre, post, then), zoom))
    }
    p.FnParam(p.AssignPattern(e.Bind(label)), pre, post, body) ->
      NoString(#(
        p.FnParam(
          p.AssignPattern(e.Destructure([#(label, label)])),
          pre,
          post,
          body,
        ),
        zoom,
      ))
    p.Labeled(l, v, pre, post, for) ->
      NeedString(fn(new) {
        #(p.Labeled(new, e.Vacant, [#(l, v), ..pre], post, for), zoom)
      })
  }
}

pub fn overwrite(zip) {
  let #(focus, zoom) = zip
  io.debug(focus)
  case focus {
    p.Exp(e.Vacant) | p.Exp(e.Record([], None)) -> fn(new) {
      #(p.Exp(e.Vacant), [
        p.RecordValue(new, [], [], p.Overwrite(e.Vacant)),
        ..zoom
      ])
    }
    p.Exp(e.Record(fields, None)) -> fn(new) {
      #(p.Exp(e.Vacant), [p.OverwriteTail(list.reverse(fields)), ..zoom])
    }
    p.Exp(item) -> fn(new) {
      #(p.Exp(e.Vacant), [p.RecordValue(new, [], [], p.Overwrite(item)), ..zoom])
    }
  }
}

pub fn tag(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Vacant) -> fn(new) { #(p.Exp(e.Tag(new)), zoom) }
    p.Exp(inner) -> fn(new) {
      #(p.Exp(e.Tag(new)), [p.CallFn([inner]), ..zoom])
    }
  }
}

pub fn match(zip) {
  let #(focus, zoom) = zip
  let new = e.Function([e.Bind("_")], e.Vacant)
  let focus = case focus {
    p.Exp(exp) -> p.Match(exp, "Ok", new, [], [], None)
    p.Match(top, label, branch, pre, post, otherwise) -> {
      let post = [#(label, branch), ..post]
      p.Match(top, "New", new, pre, post, otherwise)
    }
  }
  #(focus, zoom)
}

pub fn open_match(zip) {
  let #(focus, zoom) = zip
  let new = e.Function([e.Bind("_")], e.Vacant)
  case focus {
    p.Exp(e.Case(top, matches, None)) -> #(p.Exp(new), [
      p.CaseTail(top, matches),
      ..zoom
    ])
    p.Match(top, label, branch, pre, post, otherwise) -> {
      let matches = listx.gather_around(pre, #(label, branch), post)
      #(p.Exp(new), [p.CaseTail(top, matches), ..zoom])
    }
  }
}

pub fn perform(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Vacant) -> fn(new) { #(p.Exp(e.Perform(new)), zoom) }
    p.Exp(inner) -> fn(new) {
      #(p.Exp(e.Perform(new)), [p.CallFn([inner]), ..zoom])
    }
  }
}

pub fn builtin(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Builtin(content)) -> #(content, fn(content) {
      #(p.Exp(e.Builtin(content)), zoom)
    })
    p.Exp(_) -> #("", fn(content) { #(p.Exp(e.Builtin(content)), zoom) })
  }
}
