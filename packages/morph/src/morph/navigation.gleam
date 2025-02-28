import gleam/io
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/result.{try}
import morph/editable as e
import morph/projection as p

fn do_first(projection) {
  case projection {
    #(p.Exp(exp), zoom) ->
      case p.do_focus_at(exp, [0], zoom) {
        Ok(projection) -> do_first(projection)
        Error(_) -> projection
      }
    #(p.Assign(p.AssignStatement(p), value, pre, post, tail), zoom) -> #(
      p.Assign(p.AssignPattern(p), value, pre, post, tail),
      zoom,
    )
    #(
      p.FnParam(
        p.AssignPattern(e.Destructure([#(l, b), ..ppost])),
        pre,
        post,
        body,
      ),
      zoom,
    ) -> #(p.FnParam(p.AssignField(l, b, [], ppost), pre, post, body), zoom)
    p -> p
  }
}

fn do_last(projection) {
  let #(focus, zoom) = projection
  case focus {
    p.Exp(exp) ->
      case exp {
        e.Variable(_) -> projection
        e.Block(assigns, then, _open) ->
          do_last(#(p.Exp(then), [p.BlockTail(assigns), ..zoom]))
        e.Call(func, args) -> {
          let assert [arg, ..pre] = list.reverse(args)
          do_last(#(p.Exp(arg), [p.CallArg(func, pre, []), ..zoom]))
        }
        e.Function(params, body) ->
          do_last(#(p.Exp(body), [p.Body(params), ..zoom]))
        e.Vacant -> projection
        e.Integer(_) -> projection
        e.Binary(_) -> projection
        e.String(_) -> projection
        e.List(items, Some(tail)) ->
          do_last(#(p.Exp(tail), [p.ListTail(items), ..zoom]))
        e.List(items, None) ->
          case list.reverse(items) {
            [item, ..pre] ->
              do_last(#(p.Exp(item), [p.ListItem(pre, [], None), ..zoom]))
            [] -> projection
          }
        e.Record(fields, Some(original)) ->
          do_last(#(p.Exp(original), [p.OverwriteTail(fields), ..zoom]))
        e.Record(fields, None) ->
          case list.reverse(fields) {
            [#(l, value), ..pre] ->
              do_last(
                #(p.Exp(value), [p.RecordValue(l, pre, [], p.Record), ..zoom]),
              )
            [] -> projection
          }
        e.Select(from, label) -> #(p.Select(label, from), zoom)
        // do_last(#(p.Exp(from), [p.SelectValue(label), ..zoom]))
        e.Tag(_) -> projection
        e.Case(top, matches, Some(otherwise)) ->
          do_last(#(p.Exp(otherwise), [p.CaseTail(top, matches), ..zoom]))
        e.Case(top, matches, None) ->
          case list.reverse(matches) {
            [#(l, branch), ..pre] ->
              do_last(
                #(p.Exp(branch), [p.CaseMatch(top, l, pre, [], None), ..zoom]),
              )
            [] -> projection
          }
        e.Perform(_) -> projection
        e.Deep(_) -> projection
        e.Builtin(_) -> projection
        e.Reference(_) | e.Release(_, _, _) -> projection
      }
    p.Assign(p.AssignStatement(p), value, pre, post, tail) -> #(
      p.Assign(p.AssignPattern(p), value, pre, post, tail),
      zoom,
    )
    focus -> #(focus, zoom)
  }
}

fn pattern_next(pattern) {
  case pattern {
    p.AssignField(field, var, pre, post) ->
      Ok(p.AssignBind(field, var, pre, post))
    p.AssignBind(field, var, pre, [next, ..post]) ->
      Ok(p.AssignField(next.0, next.1, [#(field, var), ..pre], post))
    p.AssignPattern(e.Destructure([#(field, var), ..post])) ->
      Ok(p.AssignField(field, var, [], post))
    p.AssignStatement(e.Destructure([#(field, var), ..post])) ->
      Ok(p.AssignField(field, var, [], post))
    _ -> Error(Nil)
  }
}

fn pattern_previous(pattern) {
  case pattern {
    p.AssignBind(field, var, pre, post) ->
      Ok(p.AssignField(field, var, pre, post))
    p.AssignField(field, var, [next, ..pre], post) ->
      Ok(p.AssignBind(next.0, next.1, pre, [#(field, var), ..post]))
    p.AssignPattern(e.Destructure(parts)) -> {
      case list.reverse(parts) {
        [#(field, var), ..pre] -> Ok(p.AssignField(field, var, pre, []))
        _ -> Error(Nil)
      }
    }
    p.AssignStatement(e.Destructure(parts)) -> {
      case list.reverse(parts) {
        [#(field, var), ..pre] -> Ok(p.AssignField(field, var, pre, []))
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn pattern_first(pattern) {
  case pattern {
    e.Bind(_label) -> p.AssignPattern(pattern)
    e.Destructure(bindings) -> {
      let assert [#(label, var), ..post] = bindings
      p.AssignField(label, var, [], post)
    }
  }
}

fn pattern_last(pattern) {
  case pattern {
    e.Bind(_label) -> p.AssignPattern(pattern)
    e.Destructure(bindings) -> {
      let assert [#(label, var), ..pre] = list.reverse(bindings)
      p.AssignBind(label, var, pre, [])
    }
  }
}

pub fn first(exp) {
  zoom_next(exp, [])
}

pub fn zoom_next(exp, zoom) {
  case zoom {
    [] -> do_first(#(p.Exp(exp), []))
    [break, ..rest] ->
      case break {
        p.BlockValue(pattern, pre, [next, ..post], then) -> {
          let pre = [#(pattern, exp), ..pre]
          let focus = pattern_first(next.0)
          #(p.Assign(focus, next.1, pre, post, then), rest)
        }
        p.BlockValue(pattern, pre, [], then) -> {
          let assignments = list.reverse([#(pattern, exp), ..pre])
          let zoom = [p.BlockTail(assignments), ..rest]
          #(p.Exp(then), zoom)
        }
        p.BlockTail(assignments) ->
          zoom_next(e.Block(assignments, exp, True), rest)
        p.CallFn([arg, ..post]) ->
          do_first(#(p.Exp(arg), [p.CallArg(exp, [], post), ..rest]))
        p.CallFn([]) -> zoom_next(e.Call(exp, []), rest)
        p.CallArg(func, pre, [next, ..post]) ->
          do_first(
            #(p.Exp(next), [p.CallArg(func, [exp, ..pre], post), ..rest]),
          )
        // Should never happen
        p.CallArg(func, pre, []) ->
          zoom_next(e.Call(func, list.reverse([exp, ..pre])), rest)
        p.Body(args) -> zoom_next(e.Function(args, exp), rest)
        p.ListItem(pre, [next, ..post], tail) -> {
          let zoom = [p.ListItem([exp, ..pre], post, tail), ..rest]
          do_first(#(p.Exp(next), zoom))
        }
        p.ListItem(pre, [], Some(tail)) -> {
          let zoom = [p.ListTail(list.reverse([exp, ..pre])), ..rest]
          do_first(#(p.Exp(tail), zoom))
        }
        p.ListItem(pre, [], None) -> {
          let exp = e.List(list.reverse([exp, ..pre]), None)
          zoom_next(exp, rest)
        }
        p.ListTail(items) -> {
          let exp = e.List(items, Some(exp))
          zoom_next(exp, rest)
        }
        // TODO renambe labelled
        p.RecordValue(label, pre, [next, ..post], for) -> {
          let pre = [#(label, exp), ..pre]
          #(p.Label(next.0, next.1, pre, post, for), rest)
        }
        p.RecordValue(label, pre, [], p.Record) -> {
          let fields = list.reverse([#(label, exp), ..pre])
          let exp = e.Record(fields, None)
          zoom_next(exp, rest)
        }
        p.RecordValue(label, pre, [], p.Overwrite(original)) -> {
          let zoom = [p.OverwriteTail([#(label, exp), ..pre]), ..rest]
          do_first(#(p.Exp(original), zoom))
        }
        p.SelectValue(label) -> #(p.Select(label, exp), rest)
        p.OverwriteTail(fields) -> {
          let exp = e.Record(list.reverse(fields), Some(exp))
          zoom_next(exp, rest)
        }
        p.CaseTop([#(label, branch), ..post], otherwise) -> #(
          p.Match(exp, label, branch, [], post, otherwise),
          rest,
        )
        p.CaseTop([], Some(otherwise)) -> {
          let zoom = [p.CaseTail(exp, []), ..rest]
          do_first(#(p.Exp(otherwise), zoom))
        }
        p.CaseTop([], None) -> {
          let exp = e.Case(exp, [], None)
          zoom_next(exp, rest)
        }
        p.CaseMatch(top, label, pre, post, otherwise) -> {
          let pre = [#(label, exp), ..pre]
          case post, otherwise {
            [next, ..post], _ -> #(
              p.Match(top, next.0, next.1, pre, post, otherwise),
              rest,
            )
            [], Some(otherwise) -> {
              let zoom = [p.CaseTail(top, list.reverse(pre)), ..rest]
              do_first(#(p.Exp(otherwise), zoom))
            }
            [], None -> {
              let exp = e.Case(top, list.reverse(pre), None)
              zoom_next(exp, rest)
            }
          }
        }
        p.CaseTail(top, matches) -> {
          let exp = e.Case(top, matches, Some(exp))
          zoom_next(exp, rest)
        }
      }
  }
}

// exp has already been walked
pub fn zoom_previous(exp, zoom) {
  case zoom {
    [] -> do_last(#(p.Exp(exp), []))
    [break, ..rest] ->
      case break {
        p.BlockValue(pattern, pre, post, then) -> {
          #(p.Assign(pattern_last(pattern), exp, pre, post, then), rest)
        }
        p.BlockTail(assignments) ->
          case list.reverse(assignments) {
            [#(pattern, value), ..pre] ->
              do_last(
                #(p.Exp(value), [p.BlockValue(pattern, pre, [], exp), ..rest]),
              )
            [] -> zoom_previous(e.Block([], exp, True), rest)
          }
        p.CallFn(args) -> zoom_previous(e.Call(exp, args), rest)
        p.CallArg(func, [], post) ->
          do_last(#(p.Exp(func), [p.CallFn([exp, ..post]), ..rest]))
        p.CallArg(func, [next, ..pre], post) ->
          do_last(#(p.Exp(next), [p.CallArg(func, pre, [exp, ..post]), ..rest]))
        p.Body(params) -> {
          let assert [pattern, ..pre] = list.reverse(params)
          #(p.FnParam(pattern_last(pattern), pre, [], exp), rest)
        }
        p.ListTail(items) ->
          case list.reverse(items) {
            [item, ..pre] ->
              do_last(#(p.Exp(item), [p.ListItem(pre, [], Some(exp)), ..rest]))
            [] -> {
              let exp = e.List([], Some(exp))
              zoom_previous(exp, rest)
            }
          }

        p.ListItem([next, ..pre], post, tail) -> {
          let zoom = [p.ListItem(pre, [exp, ..post], tail), ..rest]
          do_last(#(p.Exp(next), zoom))
        }
        p.ListItem([], post, tail) -> {
          let exp = e.List([exp, ..post], tail)
          zoom_previous(exp, rest)
        }
        p.OverwriteTail(fields) -> {
          case list.reverse(fields) {
            [#(label, value), ..pre] -> #(p.Exp(value), [
              p.RecordValue(label, pre, [], p.Overwrite(exp)),
              ..rest
            ])
            [] -> {
              let exp = e.Record([], Some(exp))
              zoom_previous(exp, rest)
            }
          }
        }
        p.RecordValue(label, pre, post, for) -> {
          #(p.Label(label, exp, pre, post, for), rest)
        }
        p.SelectValue(label) -> zoom_previous(e.Select(exp, label), rest)
        p.CaseTail(top, matches) ->
          case list.reverse(matches) {
            [#(label, branch), ..pre] ->
              do_last(
                #(p.Exp(branch), [
                  p.CaseMatch(top, label, pre, [], Some(exp)),
                  ..rest
                ]),
              )
            [] -> #(p.Exp(top), [p.CaseTop([], Some(exp))])
          }
        p.CaseMatch(top, label, pre, post, otherwise) -> #(
          p.Match(top, label, exp, pre, post, otherwise),
          rest,
        )

        p.CaseTop(matches, otherwise) -> {
          let exp = e.Case(exp, matches, otherwise)
          zoom_previous(exp, rest)
        }
      }
  }
}

pub fn next(projection) {
  case do_first(projection) {
    p if p == projection ->
      case p {
        // in this match e is a smallest possible thing
        #(p.Exp(exp), zoom) -> zoom_next(exp, zoom)
        #(p.FnParam(pattern, pre, post, body), zoom) ->
          case pattern_next(pattern) {
            Ok(pattern) -> #(p.FnParam(pattern, pre, post, body), zoom)
            Error(Nil) -> {
              let pattern = p.assigned_pattern(pattern)
              case post {
                [] -> {
                  let break = p.Body(listx.gather_around(pre, pattern, post))
                  let zoom = [break, ..zoom]
                  do_first(#(p.Exp(body), zoom))
                }
                [param, ..post] -> {
                  let pre = [pattern, ..pre]
                  #(p.FnParam(pattern_first(param), pre, post, body), zoom)
                }
              }
            }
          }
        #(p.Assign(focus, value, pre, post, tail), zoom) ->
          case pattern_next(focus) {
            Ok(focus) -> #(p.Assign(focus, value, pre, post, tail), zoom)
            Error(Nil) -> {
              let break =
                p.BlockValue(p.assigned_pattern(focus), pre, post, tail)
              let zoom = [break, ..zoom]
              do_first(#(p.Exp(value), zoom))
            }
          }
        #(p.Label(label, value, pre, post, for), zoom) -> {
          let break = p.RecordValue(label, pre, post, for)
          let zoom = [break, ..zoom]
          do_first(#(p.Exp(value), zoom))
        }
        #(p.Select(label, from), zoom) -> {
          let exp = e.Select(from, label)
          zoom_next(exp, zoom)
        }
        #(p.Match(top, label, branch, pre, post, otherwise), zoom) -> {
          let break = p.CaseMatch(top, label, pre, post, otherwise)
          let zoom = [break, ..zoom]
          do_first(#(p.Exp(branch), zoom))
        }
      }
    projection -> projection
  }
}

pub fn previous(projection) {
  case do_last(projection) {
    p if p == projection ->
      case p {
        // in this match e is a smallest possible thing
        #(p.Exp(exp), zoom) -> zoom_previous(exp, zoom)
        #(p.FnParam(pattern, pre, post, body), zoom) ->
          case pattern_previous(pattern) {
            Ok(pattern) -> #(p.FnParam(pattern, pre, post, body), zoom)
            Error(Nil) -> {
              let pattern = p.assigned_pattern(pattern)
              case pre {
                [] -> {
                  let params = listx.gather_around(pre, pattern, post)
                  let exp = e.Function(params, body)
                  zoom_previous(exp, zoom)
                }
                [param, ..pre] -> {
                  let post = [pattern, ..post]
                  #(p.FnParam(pattern_last(param), pre, post, body), zoom)
                }
              }
            }
          }
        #(p.Assign(focus, value, pre, post, then), zoom) ->
          case pattern_previous(focus) {
            Ok(focus) -> #(p.Assign(focus, value, pre, post, then), zoom)
            Error(Nil) -> {
              let post = [#(p.assigned_pattern(focus), value), ..post]
              case pre {
                [#(pattern, value), ..pre] -> {
                  let break = p.BlockValue(pattern, pre, post, then)
                  let zoom = [break, ..zoom]
                  do_last(#(p.Exp(value), zoom))
                }
                [] -> {
                  let exp = e.Block(post, then, True)
                  zoom_previous(exp, zoom)
                }
              }
            }
          }
        #(p.Label(label, value, [next, ..pre], post, for), zoom) -> {
          let post = [#(label, value), ..post]
          let break = p.RecordValue(next.0, pre, post, for)
          let zoom = [break, ..zoom]
          do_last(#(p.Exp(next.1), zoom))
        }
        #(p.Label(label, value, [], post, for), zoom) -> {
          let fields = [#(label, value), ..post]
          let exp = case for {
            p.Record -> e.Record(fields, None)
            p.Overwrite(original) -> e.Record(fields, Some(original))
          }
          zoom_previous(exp, zoom)
        }
        #(p.Select(label, from), zoom) -> {
          do_last(#(p.Exp(from), [p.SelectValue(label), ..zoom]))
        }
        #(p.Match(top, label, value, [next, ..pre], post, otherwise), zoom) -> {
          let post = [#(label, value), ..post]
          let break = p.CaseMatch(top, next.0, pre, post, otherwise)
          let zoom = [break, ..zoom]
          do_last(#(p.Exp(next.1), zoom))
        }
        #(p.Match(top, label, value, [], post, otherwise), zoom) -> {
          let matches = [#(label, value), ..post]
          let break = p.CaseTop(matches, otherwise)
          let zoom = [break, ..zoom]
          do_last(#(p.Exp(top), zoom))
        }
      }
    projection -> projection
  }
}

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
      p.ListTail([exp, ..pre]),
      ..rest
    ])
    #(p.Label(l, v, pre, post, for), rest) -> {
      #(p.Exp(v), [p.RecordValue(l, pre, post, for), ..rest])
    }
    #(p.Exp(v), [p.RecordValue(l, pre, [#(l2, v2), ..post], for), ..rest]) -> #(
      p.Label(l2, v2, [#(l, v), ..pre], post, for),
      rest,
    )
    #(p.Exp(exp), [p.RecordValue(l, pre, [], p.Overwrite(new)), ..rest]) -> #(
      p.Exp(new),
      [p.OverwriteTail([#(l, exp), ..pre]), ..rest],
    )
    #(p.Exp(inner), [p.SelectValue(label), ..rest]) -> {
      #(p.Exp(e.Select(inner, label)), rest)
    }
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
  |> Ok
}

pub fn move_left(zip) {
  case zip {
    #(p.Exp(value), [p.BlockValue(pattern, pre, post, then), ..rest]) -> {
      let detail = case pattern {
        e.Bind(_label) -> p.AssignPattern(pattern)
        e.Destructure(bindings) -> {
          let assert [#(label, var), ..pre] = list.reverse(bindings)
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
        _ -> panic as "all ready left"
      }
    }
    #(p.Exp(a), [p.CallArg(f, [], post), ..rest]) -> {
      #(p.Exp(f), [p.CallFn([a, ..post]), ..rest])
    }
    #(p.Exp(a), [p.CallArg(f, [n, ..pre], post), ..rest]) -> {
      #(p.Exp(n), [p.CallArg(f, pre, [a, ..post]), ..rest])
    }
    #(p.Exp(body), [p.Body(args), ..rest]) -> {
      let assert [last, ..pre] = list.reverse(args)
      #(p.FnParam(p.AssignPattern(last), pre, [], body), rest)
    }
    #(p.Exp(exp), [p.ListItem([next, ..pre], post, tail), ..rest]) -> #(
      p.Exp(next),
      [p.ListItem(pre, [exp, ..post], tail), ..rest],
    )
    #(p.Exp(exp), [p.ListTail(items), ..rest]) -> {
      let assert [next, ..pre] = list.reverse(items)
      #(p.Exp(next), [p.ListItem(pre, [], Some(exp)), ..rest])
    }
    #(p.Label(l, v, [next, ..pre], post, for), zoom) -> #(p.Exp(next.1), [
      p.RecordValue(next.0, pre, [#(l, v), ..post], for),
      ..zoom
    ])
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
  |> Ok
}

pub fn increase(zip) {
  p.step(zip)
}

pub fn decrease(zip) {
  let #(focus, zoom) = zip
  case focus {
    p.Assign(detail, v, pre, post, then) -> {
      #(p.Assign(decrease_assign(detail), v, pre, post, then), zoom)
    }
    p.Exp(exp) -> {
      let assert Ok(p) = p.do_focus_at(exp, [0], zoom)
      p
    }
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
    _ -> panic as "can't decrease into assign"
  }
}

pub fn toggle_open(proj) {
  let #(focus, zoom) = proj
  let focus = case focus {
    p.Exp(e.Block(assigns, then, open)) -> p.Exp(e.Block(assigns, then, !open))
    p.Assign(label, e.Block(assigns, inner, open), pre, post, final) ->
      p.Assign(label, e.Block(assigns, inner, !open), pre, post, final)
    _ -> focus
  }
  #(focus, zoom)
}
