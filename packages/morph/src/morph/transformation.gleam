import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/result.{try}
import morph/editable as e
import morph/projection as p

pub type MaybeString {
  NeedString(fn(String) -> p.Projection)
  NoString(p.Projection)
}

// for guard
const vacant = e.Vacant

pub fn delete(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    p.Exp(e.Vacant), [p.ListItem(pre, [next, ..post], tail), ..zoom] ->
      Ok(#(p.Exp(next), [p.ListItem(pre, post, tail), ..zoom]))
    p.Exp(e.Vacant), [p.ListItem([next, ..pre], [], tail), ..zoom] ->
      Ok(#(p.Exp(next), [p.ListItem(pre, [], tail), ..zoom]))
    p.Exp(e.Vacant), [p.ListItem([], [], Some(tail)), ..zoom] ->
      Ok(#(p.Exp(tail), zoom))
    p.Exp(e.Vacant), [p.ListItem([], [], None), ..zoom] ->
      Ok(#(p.Exp(e.List([], None)), zoom))
    p.Exp(e.Vacant), [p.ListTail(elements), ..zoom] ->
      case list.reverse(elements) {
        [exp, ..pre] -> Ok(#(p.Exp(exp), [p.ListItem(pre, [], None), ..zoom]))
        [] -> Ok(#(p.Exp(e.List([], None)), zoom))
      }
    p.Exp(e.Vacant), [p.CallArg(f, pre, [next, ..post]), ..zoom] ->
      Ok(#(p.Exp(next), [p.CallArg(f, pre, post), ..zoom]))

    p.Exp(e.Vacant), [p.CallArg(f, [next, ..pre], []), ..zoom] ->
      Ok(#(p.Exp(next), [p.CallArg(f, pre, []), ..zoom]))

    p.Exp(e.Vacant), [p.CallArg(f, [], []), ..zoom] ->
      Ok(#(p.Exp(e.Call(f, [e.Vacant])), zoom))
    p.Exp(x), _ if x != vacant -> Ok(#(p.Exp(e.Vacant), zoom))
    p.Assign(p.AssignStatement(_), _, pre, [#(pattern, value), ..post], then),
      zoom
    -> Ok(#(p.Assign(p.AssignStatement(pattern), value, pre, post, then), zoom))
    p.Assign(p.AssignStatement(_), _, [#(pattern, value), ..pre], [], then),
      zoom
    -> Ok(#(p.Assign(p.AssignStatement(pattern), value, pre, [], then), zoom))
    p.Assign(p.AssignStatement(_), _, [], [], then), zoom ->
      Ok(#(p.Exp(then), zoom))
    p.Assign(
      p.AssignField(_, _, pre_p, [#(l, x), ..post_p]),
      value,
      pre,
      post,
      then,
    ),
      _
    ->
      Ok(#(
        p.Assign(p.AssignField(l, x, pre_p, post_p), value, pre, post, then),
        zoom,
      ))
    p.Assign(
      p.AssignBind(_, _, pre_p, [#(l, x), ..post_p]),
      value,
      pre,
      post,
      then,
    ),
      _
    ->
      Ok(#(
        p.Assign(p.AssignBind(l, x, pre_p, post_p), value, pre, post, then),
        zoom,
      ))
    p.Assign(
      p.AssignField(_, _, [#(l, x), ..pre_p], []),
      value,
      pre,
      post,
      then,
    ),
      _
    ->
      Ok(#(
        p.Assign(p.AssignField(l, x, pre_p, []), value, pre, post, then),
        zoom,
      ))
    p.Assign(p.AssignBind(_, _, [#(l, x), ..pre_p], []), value, pre, post, then),
      _
    ->
      Ok(#(
        p.Assign(p.AssignBind(l, x, pre_p, []), value, pre, post, then),
        zoom,
      ))
    p.Assign(p.AssignField(_, _, [], []), value, pre, post, then), _ ->
      Ok(#(
        p.Assign(p.AssignPattern(e.Destructure([])), value, pre, post, then),
        zoom,
      ))
    p.Assign(p.AssignBind(_, _, [], []), value, pre, post, then), _ ->
      Ok(#(
        p.Assign(p.AssignPattern(e.Destructure([])), value, pre, post, then),
        zoom,
      ))
    p.Assign(p.AssignPattern(e.Destructure([])), value, pre, post, then), _ ->
      Ok(#(p.Assign(p.AssignPattern(e.Bind("_")), value, pre, post, then), zoom))

    p.FnParam(p.AssignPattern(_), pre, [pattern, ..post], body), _ ->
      Ok(#(p.FnParam(p.AssignPattern(pattern), pre, post, body), zoom))
    p.FnParam(p.AssignPattern(_), [pattern, ..pre], [], body), _ ->
      Ok(#(p.FnParam(p.AssignPattern(pattern), pre, [], body), zoom))
    p.FnParam(p.AssignField(_, _, pre_p, [#(l, x), ..post_p]), pre, post, body),
      _
    ->
      Ok(#(p.FnParam(p.AssignField(l, x, pre_p, post_p), pre, post, body), zoom))
    p.FnParam(p.AssignBind(_, _, pre_p, [#(l, x), ..post_p]), pre, post, body),
      _
    ->
      Ok(#(p.FnParam(p.AssignBind(l, x, pre_p, post_p), pre, post, body), zoom))
    p.FnParam(p.AssignField(_, _, [#(l, x), ..pre_p], []), pre, post, body), _ ->
      Ok(#(p.FnParam(p.AssignField(l, x, pre_p, []), pre, post, body), zoom))
    p.FnParam(p.AssignBind(_, _, [#(l, x), ..pre_p], []), pre, post, body), _ ->
      Ok(#(p.FnParam(p.AssignBind(l, x, pre_p, []), pre, post, body), zoom))
    p.FnParam(p.AssignField(_, _, [], []), pre, post, body), _ ->
      Ok(#(p.FnParam(p.AssignPattern(e.Destructure([])), pre, post, body), zoom))
    p.FnParam(p.AssignBind(_, _, [], []), pre, post, body), _ ->
      Ok(#(p.FnParam(p.AssignPattern(e.Destructure([])), pre, post, body), zoom))
    p.FnParam(p.AssignPattern(e.Destructure([])), pre, post, body), _ ->
      Ok(#(p.FnParam(p.AssignPattern(e.Bind("_")), pre, post, body), zoom))
    p.Label(_, _, pre, [#(l, v), ..post], for), _ ->
      Ok(#(p.Label(l, v, pre, post, for), zoom))
    p.Exp(e.Vacant),
      [p.RecordValue(_label, pre, [#(l, v), ..post], for), ..zoom]
    -> Ok(#(p.Label(l, v, pre, post, for), zoom))
    p.Label(_, _, [#(l, v), ..pre], [], for), _ ->
      Ok(#(p.Label(l, v, pre, [], for), zoom))
    p.Exp(e.Vacant), [p.RecordValue(_label, [#(l, v), ..pre], [], for), ..zoom] ->
      Ok(#(p.Exp(v), [p.RecordValue(l, pre, [], for), ..zoom]))
    p.Label(_, _, [], [], p.Record), _ -> Ok(#(p.Exp(e.Record([], None)), zoom))
    p.Exp(e.Vacant), [p.RecordValue(_label, [], [], _for), ..zoom] ->
      Ok(#(p.Exp(e.Record([], None)), zoom))
    p.Match(top, _, _, pre, [#(label, branch), ..post], otherwise), zoom ->
      Ok(#(p.Match(top, label, branch, pre, post, otherwise), zoom))
    p.Match(top, _, _, [#(label, branch), ..pre], [], otherwise), zoom ->
      Ok(#(p.Match(top, label, branch, pre, [], otherwise), zoom))
    _, _ -> p.step(zip)
  }
}

pub fn assign(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    p.Exp(e.Vacant), [p.BlockTail(assigns), ..zoom] ->
      Ok(fn(pattern) {
        let zoom = [
          p.BlockValue(pattern, list.reverse(assigns), [], e.Vacant),
          ..zoom
        ]
        #(p.Exp(e.Vacant), zoom)
      })

    p.Exp(value), [p.BlockTail(assigns), ..zoom] ->
      Ok(fn(pattern) {
        let assigns = list.append(assigns, [#(pattern, value)])
        let zoom = [p.BlockTail(assigns), ..zoom]
        #(p.Exp(e.Vacant), zoom)
      })
    p.Exp(e.Vacant as value), _ ->
      Ok(fn(pattern) {
        let zoom = [p.BlockValue(pattern, [], [], value), ..zoom]
        #(p.Exp(e.Vacant), zoom)
      })
    p.Exp(value), _ ->
      Ok(fn(pattern) {
        let zoom = [p.BlockTail([#(pattern, value)]), ..zoom]
        #(p.Exp(e.Vacant), zoom)
      })
    _, _ -> Error(Nil)
  }
}

pub fn assign_before(zip) {
  case zip {
    // #(p.Exp(x), [p.ListItem(pre, post, tail), ..rest]) -> {
    //   let zoom = [p.ListItem(pre, [x, ..post], tail), ..rest]
    //   Ok(NoString(#(p.Exp(e.Vacant), zoom)))
    // }
    #(p.Assign(p.AssignStatement(pattern), value, pre, post, then), rest) -> {
      let post = [#(pattern, value), ..post]
      let build = fn(new) {
        let details = p.AssignStatement(new)
        #(p.Assign(details, e.Vacant, pre, post, then), rest)
      }
      Ok(build)
    }
    #(p.Exp(then), [p.BlockTail(lets), ..rest]) -> {
      let build = fn(new) {
        let zoom = [p.BlockValue(new, list.reverse(lets), [], then), ..rest]
        #(p.Exp(e.Vacant), zoom)
      }
      Ok(build)
    }
    #(p.Exp(then), []) -> {
      let build = fn(new) {
        #(p.Exp(e.Vacant), [p.BlockValue(new, [], [], then)])
      }
      Ok(build)
    }
    _ -> {
      use zip <- try(p.step(zip))
      assign_before(zip)
    }
  }
}

// always start from scratch
pub fn variable(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(_) -> Ok(fn(x) { #(p.Exp(e.Variable(x)), zoom) })
    _ -> Error(Nil)
  }
}

// All functions curried so calling f on one should return existing function as argument
pub fn function(source) {
  case source {
    #(p.Exp(e.Function(args, body)), zoom) ->
      Ok(fn(new) { #(p.Exp(e.Function([e.Bind(new), ..args], body)), zoom) })
    #(p.Exp(body), [p.Body(args), ..rest]) ->
      Ok(fn(new) {
        let args = list.append(args, [e.Bind(new)])
        #(p.Exp(body), [p.Body(args), ..rest])
      })
    #(p.Exp(body), zoom) ->
      Ok(fn(new) { #(p.Exp(body), [p.Body([e.Bind(new)]), ..zoom]) })
    _ -> Error(Nil)
  }
}

pub fn call(zip) {
  case zip {
    #(p.Exp(e.Call(f, args)), rest) ->
      Ok(#(p.Exp(e.Vacant), [p.CallArg(f, list.reverse(args), []), ..rest]))

    #(p.Exp(f), [p.CallFn(args), ..rest]) ->
      Ok(#(p.Exp(e.Vacant), [p.CallArg(f, [], args), ..rest]))

    #(p.Exp(f), rest) -> Ok(#(p.Exp(e.Vacant), [p.CallArg(f, [], []), ..rest]))
    _ -> Error(Nil)
  }
}

pub fn call_with(zip) {
  case zip {
    // #(p.Exp(e.Call(f, args)), rest) ->
    //   Ok(#(p.Exp(e.Vacant), [p.CallArg(f, list.reverse(args), []), ..rest]))
    // #(p.Exp(f), [p.CallFn(args), ..rest]) ->
    //   Ok(#(p.Exp(e.Vacant), [p.CallArg(f, [], args), ..rest]))
    #(p.Exp(arg), rest) -> Ok(#(p.Exp(e.Vacant), [p.CallFn([arg]), ..rest]))
    _ -> Error(Nil)
  }
}

pub fn binary(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Binary(content)) ->
      Ok(#(content, fn(content) { #(p.Exp(e.Binary(content)), zoom) }))
    p.Exp(_) -> Ok(#(<<>>, fn(content) { #(p.Exp(e.Binary(content)), zoom) }))
    _ -> Error(Nil)
  }
}

pub fn string(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.String(content)) ->
      Ok(#(content, fn(content) { #(p.Exp(e.String(content)), zoom) }))
    p.Exp(_) -> Ok(#("", fn(content) { #(p.Exp(e.String(content)), zoom) }))
    _ -> Error(Nil)
  }
}

pub fn integer(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Integer(content)) ->
      Ok(#(content, fn(content) { #(p.Exp(e.Integer(content)), zoom) }))
    p.Exp(_) -> Ok(#(0, fn(content) { #(p.Exp(e.Integer(content)), zoom) }))
    _ -> Error(Nil)
  }
}

// This is create_list
pub fn list(zip) {
  let #(focus, zoom) = zip
  case focus {
    // p.Exp(e.Vacant) -> Ok(#(p.Exp(e.List([], None)), zoom))
    p.Exp(item) -> Ok(#(p.Exp(item), [p.ListItem([], [], None), ..zoom]))
    _ -> Error(Nil)
  }
}

// TODO didn't work very well because can't extend in a list on a list
pub fn extend(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    p.Exp(e.List(items, tail)), _ ->
      Ok(NoString(#(p.Exp(e.Vacant), [p.ListItem([], items, tail), ..zoom])))

    p.Exp(exp), [p.ListItem(pre, post, tail), ..rest] ->
      Ok(
        NoString(
          #(p.Exp(e.Vacant), [p.ListItem([exp, ..pre], post, tail), ..rest]),
        ),
      )
    p.Exp(e.Record(fields, original)), _ ->
      Ok(
        NeedString(fn(new) {
          let for = case original {
            Some(original) -> p.Overwrite(original)
            None -> p.Record
          }
          #(p.Exp(e.Vacant), [p.RecordValue(new, [], fields, for), ..zoom])
        }),
      )
    p.FnParam(p.AssignPattern(e.Destructure(fields)), pre, post, body), _ ->
      Ok(
        NeedString(fn(new) {
          #(
            p.FnParam(p.AssignBind(new, new, [], fields), pre, post, body),
            zoom,
          )
        }),
      )
    _, _ -> Error(Nil)
  }
}

pub fn spread_list(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    p.Exp(exp), [p.ListItem(pre, post, None), ..rest] -> {
      let elements = listx.gather_around(pre, exp, post)
      Ok(#(p.Exp(e.Vacant), [p.ListTail(elements), ..rest]))
    }
    _, _ -> Error(Nil)
  }
}

pub fn toggle_spread(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.List(items, Some(_rest))) -> {
      Ok(#(p.Exp(e.List(items, None)), zoom))
    }
    p.Exp(e.List(items, None)) -> {
      Ok(#(p.Exp(e.List(items, Some(e.Vacant))), zoom))
    }
    p.Exp(e.Record(fields, Some(_rest))) -> {
      Ok(#(p.Exp(e.Record(fields, None)), zoom))
    }
    p.Exp(e.Record(fields, None)) -> {
      Ok(#(p.Exp(e.Record(fields, Some(e.Vacant))), zoom))
    }
    _ -> Error(Nil)
  }
}

pub fn toggle_otherwise(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Case(top, branches, Some(_rest))) -> {
      Ok(#(p.Exp(e.Case(top, branches, None)), zoom))
    }
    p.Exp(e.Case(top, branches, None)) -> {
      Ok(#(
        p.Exp(e.Case(top, branches, Some(e.Function([e.Bind("_")], e.Vacant)))),
        zoom,
      ))
    }
    _ -> Error(Nil)
  }
}

pub fn record(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Vacant) -> Ok(NoString(#(p.Exp(e.Record([], None)), zoom)))
    p.Exp(e.Record([], None)) ->
      Ok(
        NeedString(fn(new) {
          #(p.Exp(e.Record([#(new, e.Vacant)], None)), zoom)
        }),
      )
    p.Exp(item) ->
      Ok(NeedString(fn(new) { #(p.Exp(e.Record([#(new, item)], None)), zoom) }))
    p.Assign(detail, value, pre, post, then) -> {
      let detail = case detail {
        p.AssignPattern(e.Bind(var)) -> p.AssignField(var, var, [], [])
        p.AssignPattern(e.Destructure(fields)) ->
          p.AssignField("f", "f", list.reverse(fields), [])
        _ -> panic as "cant build as record"
      }
      Ok(NoString(#(p.Assign(detail, value, pre, post, then), zoom)))
    }
    p.FnParam(p.AssignPattern(e.Bind(label)), pre, post, body) ->
      Ok(
        NoString(#(
          p.FnParam(
            p.AssignPattern(e.Destructure([#(label, label)])),
            pre,
            post,
            body,
          ),
          zoom,
        )),
      )
    _ -> Error(Nil)
  }
}

pub fn select(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Vacant) ->
      Ok(fn(new) {
        #(
          p.Exp(e.Function([e.Bind("$")], e.Select(e.Variable("$"), new))),
          zoom,
        )
      })
    p.Exp(inner) -> Ok(fn(new) { #(p.Exp(e.Select(inner, new)), zoom) })
    _ -> Error(Nil)
  }
}

pub fn overwrite(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Vacant) | p.Exp(e.Record([], None)) ->
      Ok(fn(new) {
        #(p.Exp(e.Vacant), [
          p.RecordValue(new, [], [], p.Overwrite(e.Vacant)),
          ..zoom
        ])
      })
    p.Exp(e.Record(fields, None)) ->
      Ok(fn(_new) {
        #(p.Exp(e.Vacant), [p.OverwriteTail(list.reverse(fields)), ..zoom])
      })
    p.Exp(item) ->
      Ok(fn(new) {
        #(p.Exp(e.Vacant), [
          p.RecordValue(new, [], [], p.Overwrite(item)),
          ..zoom
        ])
      })

    _ -> Error(Nil)
  }
}

pub fn tag(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Vacant) -> Ok(fn(new) { #(p.Exp(e.Tag(new)), zoom) })
    p.Exp(inner) ->
      Ok(fn(new) { #(p.Exp(e.Tag(new)), [p.CallFn([inner]), ..zoom]) })
    _ -> Error(Nil)
  }
}

pub fn match(zip) {
  let #(focus, zoom) = zip
  let new_branch = e.Function([e.Bind("_")], e.Vacant)
  case focus {
    p.Exp(exp) ->
      Ok(fn(new) { #(p.Match(exp, new, new_branch, [], [], None), zoom) })
    p.Match(top, label, branch, pre, post, otherwise) -> {
      Ok(fn(new) {
        let post = [#(label, branch), ..post]
        #(p.Match(top, new, new_branch, pre, post, otherwise), zoom)
      })
    }
    _ -> Error(Nil)
  }
}

pub fn open_match(zip) {
  let #(focus, zoom) = zip
  let new = e.Function([e.Bind("_")], e.Vacant)
  case focus {
    p.Exp(e.Case(top, matches, None)) ->
      Ok(#(p.Exp(new), [p.CaseTail(top, matches), ..zoom]))
    p.Match(top, label, branch, pre, post, None) -> {
      let matches = listx.gather_around(pre, #(label, branch), post)
      Ok(#(p.Exp(new), [p.CaseTail(top, matches), ..zoom]))
    }
    _ -> Error(Nil)
  }
}

pub fn perform(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Vacant) -> Ok(fn(new) { #(p.Exp(e.Perform(new)), zoom) })
    p.Exp(inner) ->
      Ok(fn(new) { #(p.Exp(e.Perform(new)), [p.CallFn([inner]), ..zoom]) })
    _ -> Error(Nil)
  }
}

pub fn builtin(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Exp(e.Builtin(content)) ->
      Ok(#(content, fn(content) { #(p.Exp(e.Builtin(content)), zoom) }))
    p.Exp(_) -> Ok(#("", fn(content) { #(p.Exp(e.Builtin(content)), zoom) }))
    _ -> Error(Nil)
  }
}
