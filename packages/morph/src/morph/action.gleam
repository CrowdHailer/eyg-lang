import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/result.{try}
import morph/analysis
import morph/editable as e
import morph/projection as p

pub fn insert_variable(source, analysis) {
  let #(focus, zoom) = source
  use filter <- try(case focus {
    p.Exp(e.Variable(var)) -> Ok(var)
    p.Exp(_) -> Ok("")
    _ -> Error(Nil)
  })

  let vars = case analysis {
    Some(analysis) ->
      analysis.scope_vars(source, analysis)
      |> listx.key_unique
      |> listx.key_reject("_")
      |> listx.key_reject("$")
    None -> []
  }

  let rebuild = fn(var) { #(p.Exp(e.Variable(var)), zoom) }
  Ok(#(filter, vars, rebuild))
}

pub fn call_function(source, analysis) {
  let args = case analysis {
    Some(analysis) ->
      analysis.count_args(source, analysis)
      |> result.unwrap(1)
    None -> 1
  }
  case source {
    #(p.Exp(e.Call(func, args)), zoom) -> {
      let zoom = [p.CallArg(func, list.reverse(args), []), ..zoom]
      Ok(#(p.Exp(e.Vacant), zoom))
    }
    #(p.Exp(f), zoom) -> {
      let post = list.repeat(e.Vacant, args - 1)
      let zoom = [p.CallArg(f, [], post), ..zoom]
      Ok(#(p.Exp(e.Vacant), zoom))
    }
    _ -> Error(Nil)
  }
}

pub fn make_record(projection, analysis) {
  let fields = case analysis {
    Some(analysis) -> analysis.type_fields(projection, analysis)
    None -> []
  }
  case projection, fields {
    #(p.Exp(_), zoom), [#(first, _type), ..rest] -> {
      let rest =
        list.map(rest, fn(field) {
          let #(label, _type) = field
          #(label, e.Vacant)
        })
      let zoom = [p.RecordValue(first, [], rest, p.Record), ..zoom]
      Ok(Updated(#(p.Exp(e.Vacant), zoom)))
    }
    // Mostly this wasn't helpful
    // #(p.Exp(e.Vacant), zoom), _ -> {
    //   let new = e.Record([], None)
    //   Ok(Updated(#(p.Exp(new), zoom)))
    // }
    // go to field to cover case that value is vacant
    #(p.Exp(value), zoom), _ -> {
      Ok(
        Choose("", [], fn(label) {
          let zoom = [p.RecordValue(label, [], [], p.Record), ..zoom]
          #(p.Exp(value), zoom)
        }),
      )
    }
    #(p.Assign(pattern, value, pre, post, tail), zoom), _ ->
      case pattern {
        p.AssignPattern(e.Bind(var)) -> {
          let pattern = p.AssignField(var, var, [], [])
          let source = #(p.Assign(pattern, value, pre, post, tail), zoom)
          Ok(Updated(source))
        }
        _ -> Error(Nil)
      }
    #(p.FnParam(pattern, pre, post, body), zoom), _ ->
      case pattern {
        p.AssignPattern(e.Bind(var)) -> {
          let pattern = p.AssignField(var, var, [], [])
          let source = #(p.FnParam(pattern, pre, post, body), zoom)
          Ok(Updated(source))
        }
        _ -> Error(Nil)
      }
    #(p.Label(_, _, _, _, _), _), _
    | #(p.Match(_, _, _, _, _, _), _), _
    | #(p.Select(_, _), _), _
    -> Error(Nil)
  }
}

pub fn make_empty_record(projection) {
  case projection {
    #(p.Exp(_), zoom) -> Ok(#(p.Exp(e.Record([], None)), zoom))
    _ -> Error(Nil)
  }
}

pub fn overwrite_record(projection, analysis) {
  case projection {
    #(p.Exp(exp), zoom) -> {
      let fields = case analysis {
        Some(analysis) -> analysis.type_fields(projection, analysis)
        None -> []
      }
      Ok(
        #(fields, fn(label) {
          #(p.Exp(e.Vacant), [
            p.RecordValue(label, [], [], p.Overwrite(exp)),
            ..zoom
          ])
        }),
      )
    }
    _ -> Error(Nil)
  }
}

pub fn select_field(projection, analysis) {
  let fields = case analysis {
    Some(analysis) -> analysis.type_fields(projection, analysis)
    None -> []
  }
  case projection, fields {
    #(p.Exp(inner), zoom), fields -> {
      Ok(#(fields, fn(label) { #(p.Exp(e.Select(inner, label)), zoom) }))
    }
    _, _ -> Error(Nil)
  }
}

pub type Outcome(help) {
  Choose(
    filter: String,
    hints: List(#(String, help)),
    rebuild: fn(String) -> p.Projection,
  )
  Updated(projection: p.Projection)
}

pub fn make_tagged(projection, analysis) {
  let variants = case analysis {
    Some(analysis) -> analysis.type_variants(projection, analysis)
    None -> []
  }
  case projection, variants {
    #(p.Exp(e.Tag(label)), [p.CallFn(args), ..zoom]), variants ->
      Ok(
        Choose(label, variants, fn(label) {
          let zoom = [p.CallFn(args), ..zoom]
          #(p.Exp(e.Tag(label)), zoom)
        }),
      )
    #(p.Exp(inner), zoom), variants -> {
      Ok(
        Choose("", variants, fn(label) {
          let zoom = [p.CallArg(e.Tag(label), [], []), ..zoom]
          #(p.Exp(inner), zoom)
        }),
      )
    }

    _, _ -> Error(Nil)
  }
}

pub fn make_case(projection, analysis) {
  let variants = case analysis {
    Some(analysis) -> analysis.type_variants(projection, analysis)
    None -> []
  }

  case projection, variants {
    #(p.Exp(top), zoom), [#(first, _type), ..rest] -> {
      let rest =
        list.map(rest, fn(match) {
          let #(label, _type) = match
          #(label, e.Function([e.Bind("_")], e.Vacant))
        })
      let focus = p.Exp(e.Vacant)
      Ok(
        Updated(
          #(focus, [
            p.Body([e.Bind("_")]),
            p.CaseMatch(top, first, [], rest, None),
            ..zoom
          ]),
        ),
      )
    }
    #(p.Exp(top), zoom), [] -> {
      Ok(
        Choose("", [], fn(label) {
          let zoom = [
            p.Body([e.Bind("_")]),
            p.CaseMatch(top, label, [], [], None),
            ..zoom
          ]
          #(p.Exp(e.Vacant), zoom)
        }),
      )
    }
    #(p.Match(top, label, branch, pre, post, otherwise), zoom), varients -> {
      // analysis needs to be fetched from the top path
      let used = list.flatten([listx.keys(pre), [label], listx.keys(post)])
      let others = list.filter(varients, fn(v) { !list.contains(used, v.0) })

      Ok(
        Choose("", others, fn(new) {
          let zoom = [
            p.Body([e.Bind("_")]),
            p.CaseMatch(top, new, [#(label, branch), ..pre], post, otherwise),
            ..zoom
          ]
          #(p.Exp(e.Vacant), zoom)
        }),
      )
    }
    _, _ -> Error(Nil)
  }
}

pub fn make_open_case(projection, analysis) {
  let variants = case analysis {
    Some(analysis) -> analysis.type_variants(projection, analysis)
    None -> []
  }

  case projection {
    #(p.Exp(top), zoom) -> {
      Ok(
        #("", variants, fn(label) {
          let zoom = [
            p.Body([e.Bind("_")]),
            p.CaseMatch(
              top,
              label,
              [],
              [],
              Some(e.Function([e.Bind("_")], e.Vacant)),
            ),
            ..zoom
          ]
          #(p.Exp(e.Vacant), zoom)
        }),
      )
    }
    _ -> Error(Nil)
  }
}

pub fn perform(source, analysis) {
  let #(focus, zoom) = source
  let hints = case analysis {
    Some(analysis.Analysis(context:, ..)) -> context.effects
    None -> []
  }
  case focus {
    p.Exp(lift) -> {
      let rebuild = fn(label) {
        let zoom = [p.CallArg(e.Perform(label), [], []), ..zoom]
        #(p.Exp(lift), zoom)
      }
      Ok(#("", hints, rebuild))
    }
    _ -> Error(Nil)
  }
}

pub fn handle(source, _context) {
  // TODO should be the type from the function in the arg
  let effects = []
  let #(focus, zoom) = source
  case focus {
    p.Exp(lift) -> {
      let rebuild = fn(label) {
        let zoom = [
          p.Body([e.Bind("value"), e.Bind("resume")]),
          p.CallArg(e.Deep(label), [], [e.Function([e.Bind("_")], e.Vacant)]),
          ..zoom
        ]
        #(p.Exp(lift), zoom)
      }
      Ok(#("", effects, rebuild))
    }
    _ -> Error(Nil)
  }
}

pub fn insert_builtin(projection, builtins) {
  case projection {
    #(p.Exp(exp), zoom) -> {
      let filter = case exp {
        e.Builtin(id) -> id
        _ -> ""
      }
      Ok(#(filter, builtins, fn(id) { #(p.Exp(e.Builtin(id)), zoom) }))
    }
    _ -> Error(Nil)
  }
}

pub fn insert_named_reference(projection) {
  case projection {
    #(p.Exp(exp), zoom) -> {
      let current = case exp {
        e.Release(package, release, cid) -> Some(#(package, release, cid))
        _ -> None
      }
      Ok(
        #(current, fn(package, release, cid) {
          #(p.Exp(e.Release(package, release, cid)), zoom)
        }),
      )
    }
    _ -> Error(Nil)
  }
}

pub fn insert_reference(projection) {
  case projection {
    #(p.Exp(exp), zoom) -> {
      let current = case exp {
        e.Reference(id) -> id
        _ -> ""
      }
      Ok(#(current, fn(id) { #(p.Exp(e.Reference(id)), zoom) }))
    }
    _ -> Error(Nil)
  }
}

pub fn extend_before(source, _context) {
  case source {
    #(p.Exp(item), [p.ListItem(pre, post, tail), ..rest]) -> {
      let zoom = [p.ListItem(pre, [item, ..post], tail), ..rest]
      Ok(Updated(#(p.Exp(e.Vacant), zoom)))
    }
    #(p.Exp(item), [p.CallArg(func, pre, post), ..rest]) -> {
      let zoom = [p.CallArg(func, pre, [item, ..post]), ..rest]
      Ok(Updated(#(p.Exp(e.Vacant), zoom)))
    }
    #(p.Exp(tail), [p.ListTail(pre), ..rest]) -> {
      let zoom = [p.ListItem(pre, [], Some(tail)), ..rest]
      Ok(Updated(#(p.Exp(e.Vacant), zoom)))
    }
    #(p.Label(label, value, pre, post, for), zoom) -> {
      let post = [#(label, value), ..post]
      let rebuild = fn(label) {
        let zoom = [p.RecordValue(label, pre, post, for), ..zoom]
        #(p.Exp(e.Vacant), zoom)
      }
      Ok(Choose("", [], rebuild))
    }
    #(p.Assign(pattern, value, pre, post, then), zoom) -> {
      use rebuild <- try(extend_pattern_before(pattern))
      let rebuild = fn(label) {
        #(p.Assign(rebuild(label), value, pre, post, then), zoom)
      }
      Ok(Choose("", [], rebuild))
    }
    #(p.FnParam(p.AssignPattern(e.Bind(_) as pattern), pre, post, body), zoom) -> {
      let post = [pattern, ..post]
      let rebuild = fn(label) {
        #(p.FnParam(p.AssignPattern(e.Bind(label)), pre, post, body), zoom)
      }
      Ok(Choose("", [], rebuild))
    }
    #(p.FnParam(pattern, pre, post, body), zoom) -> {
      use rebuild <- try(extend_pattern_before(pattern))
      let rebuild = fn(label) {
        #(p.FnParam(rebuild(label), pre, post, body), zoom)
      }
      Ok(Choose("", [], rebuild))
    }

    _ -> Error(Nil)
  }
}

fn extend_pattern_before(pattern) {
  case pattern {
    p.AssignBind(field, var, pre, post) | p.AssignField(field, var, pre, post) -> {
      Ok(fn(label) { p.AssignBind(label, label, pre, [#(field, var), ..post]) })
    }
    _ -> Error(Nil)
  }
}

pub fn extend_after(source, _context) {
  case source {
    #(p.Exp(item), [p.ListItem(pre, post, tail), ..rest]) -> {
      let zoom = [p.ListItem([item, ..pre], post, tail), ..rest]
      Ok(Updated(#(p.Exp(e.Vacant), zoom)))
    }
    #(p.Exp(item), [p.CallArg(func, pre, post), ..rest]) -> {
      let zoom = [p.CallArg(func, [item, ..pre], post), ..rest]
      Ok(Updated(#(p.Exp(e.Vacant), zoom)))
    }
    #(p.Label(label, value, pre, post, for), zoom) -> {
      let pre = [#(label, value), ..pre]
      let rebuild = fn(label) {
        let zoom = [p.RecordValue(label, pre, post, for), ..zoom]
        #(p.Exp(e.Vacant), zoom)
      }
      Ok(Choose("", [], rebuild))
    }
    #(p.Assign(pattern, value, pre, post, then), zoom) -> {
      use rebuild <- try(extend_pattern_after(pattern))
      let rebuild = fn(label) {
        #(p.Assign(rebuild(label), value, pre, post, then), zoom)
      }
      Ok(Choose("", [], rebuild))
    }
    #(p.FnParam(p.AssignPattern(e.Bind(_) as pattern), pre, post, body), zoom) -> {
      let pre = [pattern, ..pre]
      let rebuild = fn(label) {
        #(p.FnParam(p.AssignPattern(e.Bind(label)), pre, post, body), zoom)
      }
      Ok(Choose("", [], rebuild))
    }
    #(p.FnParam(pattern, pre, post, body), zoom) -> {
      use rebuild <- try(extend_pattern_after(pattern))
      let rebuild = fn(label) {
        #(p.FnParam(rebuild(label), pre, post, body), zoom)
      }
      Ok(Choose("", [], rebuild))
    }

    _ -> Error(Nil)
  }
}

fn extend_pattern_after(pattern) {
  case pattern {
    p.AssignBind(field, var, pre, post) | p.AssignField(field, var, pre, post) -> {
      Ok(fn(label) { p.AssignBind(label, label, [#(field, var), ..pre], post) })
    }
    _ -> Error(Nil)
  }
}
