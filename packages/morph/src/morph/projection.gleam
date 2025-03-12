import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import morph/editable as e

// record goes through field and bind at same level assign uses path approach
// No reverseing needed of final accumutator,
// The zoom list builds from the bottom of the tree and at each step the accumulator is 
// everything within the tree
pub fn path_to_zoom(zoom, acc) {
  case zoom {
    [] -> acc
    [z, ..rest] -> {
      let acc = case z {
        BlockValue(pre: pre, ..) -> [list.length(pre), 1, ..acc]
        BlockTail(assigns) -> [list.length(assigns), ..acc]
        Body(args) -> [list.length(args), ..acc]
        CallFn(_) -> [0, ..acc]
        CallArg(pre: pre, ..) -> [list.length(pre) + 1, ..acc]
        ListItem(pre: pre, ..) -> [list.length(pre), ..acc]
        ListTail(items) -> [list.length(items), ..acc]
        // label is first value so exp is one higher than list of pre 
        RecordValue(pre: pre, ..) -> [list.length(pre) * 2 + 1, ..acc]
        SelectValue(..) -> [0, ..acc]
        OverwriteTail(fields: fields) -> [list.length(fields) + 1, ..acc]
        CaseTop(_branches, _otherwise) -> [0, ..acc]
        CaseMatch(pre: pre, ..) -> [list.length(pre) + 1, 0, ..acc]
        CaseTail(branches: branches, ..) -> [list.length(branches) + 1, ..acc]
      }
      path_to_zoom(rest, acc)
    }
  }
}

// when adding the top layer the path needs to be appended to the end
pub fn path(projection) {
  let #(focus, zoom) = projection
  let rev = list.reverse(path_to_zoom(zoom, []))
  case focus {
    Exp(_) -> rev
    FnParam(AssignStatement(_), _pre, _post, _body) ->
      panic as "fnparams dont have a statement focus"
    FnParam(AssignPattern(_), pre, _post, _body) -> [list.length(pre), ..rev]
    FnParam(AssignField(_, _, ppre, _), pre, _post, _body) -> {
      [list.length(ppre) * 2, list.length(pre), ..rev]
    }
    FnParam(AssignBind(_, _, ppre, _), pre, _post, _body) -> {
      [list.length(ppre) * 2 + 1, list.length(pre), ..rev]
    }
    Label(_label, _value, pre, _post, _for) -> [list.length(pre) * 2, ..rev]
    Select(_label, _value) -> [1, ..rev]
    Assign(AssignStatement(_), _value, pre, _post, _then) -> [
      list.length(pre),
      ..rev
    ]
    Assign(AssignPattern(_), _value, pre, _post, _then) -> [
      0,
      list.length(pre),
      ..rev
    ]
    Assign(AssignField(_, _, ppre, _), _value, pre, _post, _then) -> {
      [list.length(ppre) * 2, 0, list.length(pre), ..rev]
    }
    Assign(AssignBind(_, _, ppre, _), _value, pre, _post, _then) -> {
      [list.length(ppre) * 2 + 1, 0, list.length(pre), ..rev]
    }
    Match(_top, _label, _branch, pre, _post, _otherwise) -> {
      [list.length(pre) + 1, ..rev]
    }
  }
  |> list.reverse
}

pub fn focus_at(ast, path) {
  let assert Ok(projection) = do_focus_at(ast, path, [])
  projection
}

pub fn focus_in_block(assigns, then, path, acc) {
  let assert [i, ..rest] = path
  case i == list.length(assigns) {
    True -> do_focus_at(then, rest, [BlockTail(assigns), ..acc])
    False -> {
      let assert Ok(#(pre, #(pattern, value), post)) =
        listx.split_around(assigns, i)
      case rest {
        [] ->
          Ok(#(Assign(AssignStatement(pattern), value, pre, post, then), acc))
        [0] ->
          Ok(#(Assign(AssignPattern(pattern), value, pre, post, then), acc))
        [0, i] -> {
          case pattern {
            e.Destructure(fields) -> {
              let assert Ok(detail) = {
                let assert Ok(#(pre, #(label, var), post)) =
                  listx.split_around(fields, i / 2)

                case i % 2 {
                  0 -> Ok(AssignField(label, var, pre, post))
                  1 -> Ok(AssignBind(label, var, pre, post))
                  _ -> Error("impossible result")
                }
              }
              Ok(#(Assign(detail, value, pre, post, then), acc))
            }
            _ -> Error("bad pattern path")
          }
        }
        [1, ..rest] ->
          do_focus_at(value, rest, [BlockValue(pattern, pre, post, then), ..acc])
        _ -> Error("bad sub in block")
      }
    }
  }
}

pub fn zoom_in(proj) {
  let #(focus, zoom) = proj
  do_zoom_in(focus, zoom)
}

fn do_zoom_in(focus, zoom) {
  case focus {
    Exp(ast) ->
      case do_focus_at(ast, [0], zoom) {
        Ok(#(focus, zoom)) -> do_zoom_in(focus, zoom)
        Error(_) -> #(focus, zoom)
      }
    _ -> #(focus, zoom)
  }
}

// TODO make private but need a step in function for naviagtion
pub fn do_focus_at(ast, path, acc) {
  case ast, path {
    exp, [] -> Ok(#(Exp(exp), acc))
    e.Block(assigns, then, _), _ -> {
      focus_in_block(assigns, then, path, acc)
    }
    e.Function(params, body), [i, ..rest] -> {
      case i == list.length(params) {
        True -> do_focus_at(body, rest, [Body(params), ..acc])
        False -> {
          let assert Ok(#(pre, p, post)) = listx.split_around(params, i)
          let assert Ok(detail) = case rest {
            [] -> Ok(AssignPattern(p))
            [i] -> {
              case p {
                e.Destructure(fields) -> {
                  let assert Ok(detail) = {
                    let assert Ok(#(pre, #(label, var), post)) =
                      listx.split_around(fields, i / 2)

                    case i % 2 {
                      0 -> Ok(AssignField(label, var, pre, post))
                      1 -> Ok(AssignBind(label, var, pre, post))
                      _ -> Error("impossible result")
                    }
                  }
                  Ok(detail)
                }
                _ -> Error("bad pattern path")
              }
            }
            _ -> Error("bad function path")
          }
          Ok(#(FnParam(detail, pre, post, body), acc))
        }
      }
    }
    e.Call(func, args), [0, ..rest] ->
      do_focus_at(func, rest, [CallFn(args), ..acc])
    e.Call(func, args), [i, ..rest] -> {
      let assert Ok(#(pre, value, post)) = listx.split_around(args, i - 1)
      do_focus_at(value, rest, [CallArg(func, pre, post), ..acc])
    }
    e.List(items, tail), [i, ..rest] -> {
      case i == list.length(items), tail {
        True, Some(tail) -> do_focus_at(tail, rest, [ListTail(items), ..acc])
        False, _ -> {
          let assert Ok(#(pre, value, post)) = listx.split_around(items, i)
          do_focus_at(value, rest, [ListItem(pre, post, tail), ..acc])
        }
        _, _ -> Error("bad list")
      }
    }
    e.Record(fields, original), [i, ..rest] -> {
      let field_index = i / 2
      case field_index == list.length(fields), original {
        True, Some(original) ->
          do_focus_at(original, rest, [OverwriteTail(fields), ..acc])
        False, _ -> {
          let assert Ok(#(pre, #(label, value), post)) =
            listx.split_around(fields, field_index)
          let for = case original {
            None -> Record
            Some(original) -> Overwrite(original)
          }
          case i % 2 == 0 {
            True ->
              case rest {
                [] -> Ok(#(Label(label, value, pre, post, for), acc))
                _ -> Error("cant focus within label")
              }
            False ->
              do_focus_at(value, rest, [
                RecordValue(label, pre, post, for),
                ..acc
              ])
          }
        }
        _, _ -> Error("invalid record")
      }
    }
    e.Select(from, label), [0, ..rest] -> {
      let acc = [SelectValue(label), ..acc]
      do_focus_at(from, rest, acc)
    }
    e.Select(from, label), [1] -> Ok(#(Select(label, from), acc))
    e.Case(top, matches, otherwise), [0, ..rest] -> {
      let acc = [CaseTop(matches, otherwise), ..acc]
      do_focus_at(top, rest, acc)
    }
    e.Case(top, matches, otherwise), [i, ..rest] -> {
      let i = i - 1
      case i == list.length(matches), otherwise {
        True, Some(tail) ->
          do_focus_at(tail, rest, [CaseTail(top, matches), ..acc])
        False, _ -> {
          let assert Ok(#(pre, #(label, branch), post)) =
            listx.split_around(matches, i)
          case rest {
            [0, ..rest] ->
              do_focus_at(branch, rest, [
                CaseMatch(top, label, pre, post, otherwise),
                ..acc
              ])
            [] -> Ok(#(Match(top, label, branch, pre, post, otherwise), acc))
            _ -> Error("bad branch")
          }
        }
        _, _ -> Error("bad case")
      }
    }
    _, _ -> Error("bad path into projection")
  }
}

pub type Projection =
  #(Focus, List(Break))

pub type AssignFocus {
  // TODO remove
  AssignStatement(e.Pattern)
  AssignPattern(e.Pattern)
  AssignField(
    field: String,
    var: String,
    pre: List(#(String, String)),
    post: List(#(String, String)),
  )
  AssignBind(
    field: String,
    var: String,
    pre: List(#(String, String)),
    post: List(#(String, String)),
  )
}

pub fn assigned_pattern(focus) {
  case focus {
    AssignStatement(p) | AssignPattern(p) -> p
    AssignField(l, v, pre, post) | AssignBind(l, v, pre, post) ->
      e.Destructure(listx.gather_around(pre, #(l, v), post))
  }
}

pub type Focus {
  Exp(e.Expression)
  Assign(
    focus: AssignFocus,
    value: e.Expression,
    pre: List(#(e.Pattern, e.Expression)),
    post: List(#(e.Pattern, e.Expression)),
    tail: e.Expression,
  )
  FnParam(
    pattern: AssignFocus,
    pre: List(e.Pattern),
    post: List(e.Pattern),
    body: e.Expression,
  )
  Label(
    label: String,
    value: e.Expression,
    pre: List(#(String, e.Expression)),
    post: List(#(String, e.Expression)),
    for: WithLabel,
  )
  Select(label: String, from: e.Expression)
  Match(
    top: e.Expression,
    label: String,
    branch: e.Expression,
    pre: List(#(String, e.Expression)),
    post: List(#(String, e.Expression)),
    otherwise: Option(e.Expression),
  )
}

pub type WithLabel {
  Record
  Overwrite(original: e.Expression)
}

fn text_from_pattern(detail) {
  case detail {
    AssignStatement(_) -> Error(Nil)
    AssignPattern(e.Bind(var)) ->
      Ok(#(var, fn(new) { AssignPattern(e.Bind(new)) }))
    AssignPattern(e.Destructure(_)) -> Error(Nil)
    AssignField(label, var, pre, post) ->
      Ok(#(label, fn(new) { AssignField(new, var, pre, post) }))
    AssignBind(label, var, pre, post) ->
      Ok(#(var, fn(new) { AssignBind(label, new, pre, post) }))
  }
}

// scope is a bad name due to variable scope
// lens?
pub fn text(scope) {
  let #(focus, zoom) = scope
  case focus {
    Exp(exp) -> {
      use #(content, build) <- try(case exp {
        e.Variable(x) -> Ok(#(x, e.Variable))
        e.String(content) -> Ok(#(content, e.String))
        e.Select(inner, label) -> Ok(#(label, e.Select(inner, _)))
        e.Tag(content) -> Ok(#(content, e.Tag))
        e.Perform(label) -> Ok(#(label, e.Perform))
        e.Deep(label) -> Ok(#(label, e.Deep))
        e.Builtin(identifier) -> Ok(#(identifier, e.Builtin))
        _ -> Error(Nil)
      })
      Ok(#(content, fn(new) { #(Exp(build(new)), zoom) }))
    }
    Assign(detail, value, pre, post, then) -> {
      use #(content, build) <- try(text_from_pattern(detail))
      Ok(
        #(content, fn(new) {
          #(Assign(build(new), value, pre, post, then), zoom)
        }),
      )
    }
    FnParam(detail, pre, post, body) -> {
      use #(content, build) <- try(text_from_pattern(detail))
      Ok(#(content, fn(new) { #(FnParam(build(new), pre, post, body), zoom) }))
    }
    Label(label, value, pre, post, for) ->
      Ok(#(label, fn(new) { #(Label(new, value, pre, post, for), zoom) }))
    Select(label, from) -> Ok(#(label, fn(new) { #(Select(new, from), zoom) }))
    Match(top, label, branch, pre, post, otherwise) -> {
      Ok(
        #(label, fn(new) {
          #(Match(top, new, branch, pre, post, otherwise), zoom)
        }),
      )
    }
  }
}

// does Field and Field split have the same kind

pub type Break {
  BlockValue(
    pattern: e.Pattern,
    pre: List(#(e.Pattern, e.Expression)),
    post: List(#(e.Pattern, e.Expression)),
    then: e.Expression,
  )
  BlockTail(assignments: List(#(e.Pattern, e.Expression)))
  CallFn(args: List(e.Expression))
  CallArg(func: e.Expression, pre: List(e.Expression), post: List(e.Expression))
  Body(args: List(e.Pattern))
  ListItem(
    pre: List(e.Expression),
    post: List(e.Expression),
    tail: Option(e.Expression),
  )
  ListTail(items: List(e.Expression))
  RecordValue(
    label: String,
    pre: List(#(String, e.Expression)),
    post: List(#(String, e.Expression)),
    for: WithLabel,
  )
  SelectValue(label: String)
  OverwriteTail(fields: List(#(String, e.Expression)))
  CaseTop(
    branches: List(#(String, e.Expression)),
    otherwise: Option(e.Expression),
  )
  CaseMatch(
    top: e.Expression,
    label: String,
    pre: List(#(String, e.Expression)),
    post: List(#(String, e.Expression)),
    otherwise: Option(e.Expression),
  )
  CaseTail(top: e.Expression, branches: List(#(String, e.Expression)))
}

pub fn rebuild(zip) {
  let #(focus, zoom) = zip
  case focus, zoom {
    Exp(e), [] -> e
    _, _ -> {
      let assert Ok(zip) = step(zip)
      rebuild(zip)
    }
  }
}

// ok makes a lot of gc can pass 2 arg
pub fn step(zip) {
  let #(focus, zoom) = zip
  case focus {
    Exp(exp) ->
      case zoom {
        [] -> Error(Nil)
        [break, ..rest] -> {
          case break {
            BlockValue(p, pre, post, then) ->
              Ok(#(Assign(AssignStatement(p), exp, pre, post, then), rest))
            _ -> Ok(#(Exp(unbreak(exp, break)), rest))
          }
        }
      }
    Assign(AssignStatement(p), value, pre, post, then) ->
      Ok(#(
        Exp(e.Block(listx.gather_around(pre, #(p, value), post), then, True)),
        zoom,
      ))
    Assign(AssignPattern(p), value, pre, post, then) ->
      Ok(#(Assign(AssignStatement(p), value, pre, post, then), zoom))
    Assign(detail, value, pre, post, then) ->
      Ok(#(
        Assign(AssignPattern(assigned_pattern(detail)), value, pre, post, then),
        zoom,
      ))
    FnParam(AssignPattern(p), pre, post, body) ->
      Ok(#(Exp(e.Function(listx.gather_around(pre, p, post), body)), zoom))
    FnParam(detail, pre, post, body) ->
      Ok(#(
        FnParam(AssignPattern(assigned_pattern(detail)), pre, post, body),
        zoom,
      ))
    Label(l, value, pre, post, for) -> {
      let original = case for {
        Record -> None
        Overwrite(original) -> Some(original)
      }
      Ok(#(
        Exp(e.Record(listx.gather_around(pre, #(l, value), post), original)),
        zoom,
      ))
    }
    Select(label, from) -> {
      Ok(#(Exp(e.Select(from, label)), zoom))
    }

    Match(top, label, branch, pre, post, otherwise) -> {
      // match is a label and branch
      let matches = listx.gather_around(pre, #(label, branch), post)
      Ok(#(Exp(e.Case(top, matches, otherwise)), zoom))
    }
  }
}

fn unbreak(exp, break) {
  case break {
    BlockTail(assigments) -> e.Block(assigments, exp, True)
    BlockValue(var, pre, post, then) ->
      e.Block(listx.gather_around(pre, #(var, exp), post), then, True)
    CallFn(args) -> e.Call(exp, args)
    CallArg(f, pre, post) -> e.Call(f, listx.gather_around(pre, exp, post))
    Body(args) -> e.Function(args, exp)
    ListItem(pre, post, tail) ->
      e.List(listx.gather_around(pre, exp, post), tail)
    ListTail(items) -> e.List(items, Some(exp))
    RecordValue(label, pre, post, Record) ->
      e.Record(listx.gather_around(pre, #(label, exp), post), None)
    RecordValue(label, pre, post, Overwrite(original)) ->
      e.Record(listx.gather_around(pre, #(label, exp), post), Some(original))
    SelectValue(label) -> e.Select(exp, label)
    OverwriteTail(fields) -> e.Record(list.reverse(fields), Some(exp))
    CaseTop(matches, otherwise) -> e.Case(exp, matches, otherwise)
    CaseMatch(top, label, pre, post, otherwise) -> {
      let branches = listx.gather_around(pre, #(label, exp), post)
      e.Case(top, branches, otherwise)
    }
    CaseTail(top, branches) -> e.Case(top, branches, Some(exp))
  }
}

pub fn blank(projection) {
  case projection {
    #(Exp(e.Vacant), []) -> True
    _ -> False
  }
}
