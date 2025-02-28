import easel/location.{type Location, Location, child, focused, open}
import eyg/analysis/jm/type_ as t
import eyg/editor/v1/app.{SelectNode}
import eyg/editor/v1/view/type_
import eyg/ir/tree as ir
import eyg/runtime/value as old_value
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute.{class, classes, style} as a
import lustre/element.{text}
import lustre/element/html.{pre, span}
import lustre/event.{on_click}
import plinth/browser/event as pevent

pub fn render(source, selection, inferred) {
  let loc = Location([], Some(selection), False)
  pre(
    [
      a.attribute("tabindex", "0"),
      a.attribute("autofocus", "true"),
      // a.autofocus(True),
      event.on("keydown", fn(event) {
        let assert Ok(event) = pevent.cast_keyboard_event(event)
        let key = pevent.key(event)
        let shift = pevent.shift_key(event)
        let ctrl = pevent.ctrl_key(event)
        let alt = pevent.alt_key(event)
        case key {
          "Alt" | "Ctrl" | "Shift" | "Tab" -> Error([])
          "F1"
          | "F2"
          | "F3"
          | "F4"
          | "F5"
          | "F6"
          | "F7"
          | "F8"
          | "F9"
          | "F10"
          | "F11"
          | "F12" -> Error([])
          k if shift -> {
            pevent.prevent_default(event)
            Ok(app.Keypress(string.uppercase(k)))
          }
          _ if ctrl || alt -> Error([])
          k -> {
            pevent.prevent_default(event)
            Ok(app.Keypress(k))
          }
        }
      }),
      style([#("cursor", "pointer")]),
      class("w-full max-w-6xl"),
    ],
    do_render(source, "\n", loc, inferred),
  )
}

fn click(loc: Location) {
  on_click(SelectNode(loc.path))
}

pub fn do_render(exp: ir.Node(_), br, loc, inferred) {
  case exp.0 {
    ir.Variable(var) -> [variable(var, loc, inferred)]
    ir.Lambda(param, body) -> [lambda(param, body, br, loc, inferred)]
    ir.Apply(func, arg) -> call(func, arg, br, loc, inferred)
    ir.Let(label, value, then) ->
      assigment(label, value, then, br, loc, inferred)
    ir.Binary(value) -> [binary(value, loc, inferred)]
    ir.String(value) -> [string(value, loc, inferred)]
    ir.Integer(value) -> [integer(value, loc, inferred)]
    ir.Tail -> [
      span(
        [click(loc), classes(highlight(focused(loc), error(loc, inferred)))],
        [text("[]")],
      ),
    ]
    ir.Cons -> [
      // maybe gray but probably better rendering in apply
      span(
        [
          click(loc),
          classes([
            #("text-gray-400", True),
            ..highlight(focused(loc), error(loc, inferred))
          ]),
        ],
        [text("cons")],
      ),
    ]
    ir.Vacant -> [vacant(loc, inferred)]
    ir.Empty -> [
      span(
        [click(loc), classes(highlight(focused(loc), error(loc, inferred)))],
        [text("{}")],
      ),
    ]
    ir.Extend(label) -> [extend(label, loc, inferred)]
    ir.Select(label) -> [select(label, loc, inferred)]
    ir.Overwrite(label) -> [overwrite(label, loc, inferred)]
    ir.Tag(label) -> [tag(label, loc, inferred)]
    ir.Case(label) -> [match(label, br, loc, inferred)]
    ir.NoCases -> [
      span(
        [
          click(loc),
          classes([
            #("text-gray-400", True),
            ..highlight(focused(loc), error(loc, inferred))
          ]),
        ],
        [text("nocases")],
      ),
    ]
    ir.Perform(label) -> [perform(label, loc, inferred)]
    ir.Handle(label) -> [handle(label, loc, inferred)]
    ir.Builtin(id) -> [builtin(id, loc, inferred)]
    ir.Reference(id) -> [builtin(id, loc, inferred)]
    ir.Release(package, release, _id) -> [
      // TODO use id
      builtin("@" <> package <> ":" <> int.to_string(release), loc, inferred),
    ]
  }
}

fn render_block(exp: ir.Node(_), br, loc, inferred) {
  case exp.0 {
    ir.Let(_, _, _) ->
      case open(loc) {
        True -> {
          let br_inner = string.append(br, "  ")
          list.flatten([
            [text(string.append("{", br_inner))],
            do_render(exp, br_inner, loc, inferred),
            [text(string.append(br, "}"))],
          ])
        }
        False -> [span([click(loc)], [text("{ ... }")])]
      }
    _ -> do_render(exp, br, loc, inferred)
  }
}

fn highlight(target, alert) {
  // let colour = case target, alert {
  //   True, _ -> [#("border-b-2", True), #("border-indigo-300", True)]
  //   _, True -> [#("border-b-2", False), #("bg-red-100", True)]
  //   False, False -> [#("border-b-2", False), #("border-indigo-300", True)]
  // }
  [
    #("border-b-2", target),
    #("border-indigo-300", True),
    #("rounded", True),
    #("bg-red-200", alert),
  ]
}

fn variable(var, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)

  [classes(highlight(target, alert)), click(loc)]
  |> span([text(var)])
}

fn builtin(var, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)

  [classes([#("italic", True), ..highlight(target, alert)]), click(loc)]
  |> span([text(var)])
}

fn lambda(param, body, br, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)

  [classes(highlight(target, alert))]
  |> span([
    span([click(loc)], [text(param), text(" -> ")]),
    ..render_block(body, br, child(loc, 0), inferred)
  ])
}

fn render_branch(
  label,
  then: ir.Node(_),
  otherwise: ir.Node(_),
  br,
  loc_branch,
  loc_otherwise,
  inferred,
) {
  let loc_match = child(loc_branch, 0)
  let loc_then = child(loc_branch, 1)
  let match =
    [
      click(loc_match),
      classes([
        #("text-blue-500", True),
        ..highlight(focused(loc_match), error(loc_match, inferred))
      ]),
    ]
    |> span([text(label)])
  let branch = render_block(then, br, loc_then, inferred)
  [
    text(br),
    span(
      [classes(highlight(focused(loc_branch), error(loc_branch, inferred)))],
      [match, text(" "), ..branch],
    ),
    ..case otherwise.0 {
      ir.NoCases -> [
        text(br),
        span([class("text-gray-400"), click(loc_otherwise)], [
          text("-- closed --"),
        ]),
      ]
      ir.Apply(#(ir.Apply(#(ir.Case(label), _), then), _), otherwise) ->
        render_branch(
          label,
          then,
          otherwise,
          br,
          child(loc_otherwise, 0),
          child(loc_otherwise, 1),
          inferred,
        )
      _ -> [text(br), ..do_render(otherwise, br, loc_otherwise, inferred)]
    }
  ]
}

// case can only be applied with literal or var to correct things
// call with binary is error
// apply to just a case could leave it as ++
// nocases should be rendered alone as empty match
fn call(func: ir.Node(_), arg: ir.Node(_), br, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)

  // not target but any selected
  let inner = case func.0, arg.0 {
    ir.Apply(#(ir.Case(label), _), then), _ -> {
      let loc_branch = child(loc, 0)
      let loc_otherwise = child(loc, 1)
      case open(loc_branch) || open(loc_otherwise) {
        True -> {
          let pre = [
            span([click(loc)], [
              span([class("text-gray-400")], [text("match")]),
              text(" {"),
            ]),
          ]
          let branches =
            render_branch(
              label,
              then,
              arg,
              string.append(br, "  "),
              loc_branch,
              loc_otherwise,
              inferred,
            )
          let post = [text(br), text("}")]
          list.flatten([pre, branches, post])
        }
        False -> [
          span([click(loc_branch)], [
            span([class("text-gray-400")], [text("match")]),
            text(" { ... }"),
          ]),
        ]
      }
    }
    ir.Apply(#(ir.Extend(label), _), element), _ ->
      list.flatten([
        [
          text("{"),
          span(
            {
              let loc = child(child(loc, 0), 0)
              [
                click(loc),
                classes([
                  #("text-blue-700", True),
                  ..highlight(focused(loc), error(loc, inferred))
                ]),
              ]
            },
            [text(label)],
          ),
          text(": "),
        ],
        render_block(element, br, child(child(loc, 0), 1), inferred),
        [text(", ")],
        render_block(arg, br, child(loc, 1), inferred),
        [text("}")],
      ])
    ir.Apply(#(ir.Cons, _), element), _ -> {
      let root = #(child(child(loc, 0), 1), element)
      let #(elements, tail) = gather_list(arg, child(loc, 1), [root])

      let multiline = list.length(elements) > 3
      let br_inner = string.append(br, "  ")
      let separator = case multiline {
        False -> ", "
        True -> br_inner
      }

      let rendered =
        list.map(list.reverse(elements), fn(pair) {
          let #(loc, e) = pair
          render_block(e, br_inner, loc, inferred)
        })
        |> list.flatten
        |> list.intersperse(text(separator))

      let pre = case multiline {
        True -> string.append("[", br_inner)
        False -> "["
      }
      list.flatten([
        [text(pre)],
        rendered,
        case tail {
          None -> [
            text(case multiline {
              False -> "]"
              True -> string.append(br, "]")
            }),
          ]
          Some(#(other, loc)) -> [
            text(separator),
            text(".."),
            ..render_block(other, br, loc, inferred)
            |> list.append([text("]")])
          ]
        },
      ])
    }

    // list.flatten([
    //   [text("[")],
    //   render_block(element, br, child(child(loc, 0), 1), inferred),
    //   [text(separator)],
    //   render_block(arg, br, child(loc, 1), inferred),
    //   [text("]")],
    // ])
    ir.Select(_), _ ->
      list.flatten([
        render_block(arg, br, child(loc, 1), inferred),
        render_block(func, br, child(loc, 0), inferred),
      ])
    _, _ ->
      // arg becomes then
      list.flatten([
        render_block(func, br, child(loc, 0), inferred),
        [text("(")],
        render_block(arg, br, child(loc, 1), inferred),
        [text(")")],
      ])
  }

  [span([classes(highlight(target, alert))], inner)]
}

fn gather_list(tail, loc, acc) {
  let #(exp, _meta) = tail
  case exp {
    ir.Apply(#(ir.Apply(#(ir.Cons, _), element), _), tail) ->
      gather_list(tail, child(loc, 1), [
        #(child(child(loc, 0), 1), element),
        ..acc
      ])
    ir.Tail -> #(acc, None)
    _ -> #(acc, Some(#(tail, loc)))
  }
}

fn assigment(label, value, then, br, loc, inferred) {
  let active = focused(loc)
  let alert = error(loc, inferred)

  let assignment = [
    span([click(loc)], [
      span([class("text-gray-400")], [text("let ")]),
      text(label),
      text(" = "),
    ]),
    ..render_block(value, br, child(loc, 0), inferred)
  ]
  let el = span([classes(highlight(active, alert))], assignment)
  [el, text(br), ..do_render(then, br, child(loc, 1), inferred)]
}

fn error(loc: Location, inferred) {
  case inferred {
    Some(#(_sub, _next, types)) ->
      case dict.get(types, list.reverse(loc.path)) {
        Ok(Error(_)) -> True
        _ -> False
      }
    None -> False
  }
}

fn binary(value, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)
  let content = old_value.print_bit_string(value)
  [click(loc), classes([#("text-green-500", True), ..highlight(target, alert)])]
  |> span([text(content)])
}

fn string(value, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)
  let value = case string.split_once(value, "\n") {
    Error(Nil) -> value
    Ok(#(head, _)) -> string.append(head, "...")
  }
  let content = string.concat(["\"", value, "\""])
  [click(loc), classes([#("text-green-500", True), ..highlight(target, alert)])]
  |> span([text(content)])
}

fn integer(value, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)
  [
    click(loc),
    classes([#("text-purple-500", True), ..highlight(target, alert)]),
  ]
  |> span([text(int.to_string(value))])
}

fn vacant(loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)
  let content = case inferred {
    Some(#(sub, _next, types)) ->
      case dict.get(types, list.reverse(loc.path)) {
        Ok(inferred) ->
          case inferred {
            Ok(t) -> {
              let t = t.resolve(t, sub)
              type_.render_type(t)
            }

            Error(#(r, t1, t2)) -> type_.render_failure(r, t1, t2)
          }
        Error(Nil) -> "invalid selection"
      }
    None -> "todo"
  }
  [click(loc), classes([#("text-red-500", True), ..highlight(target, alert)])]
  |> span([text(content)])
}

fn extend(label, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)

  [click(loc), classes([#("text-blue-700", True), ..highlight(target, alert)])]
  |> span([text(string.append("+", label))])
}

fn select(label, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)

  [click(loc), classes([#("text-blue-700", True), ..highlight(target, alert)])]
  |> span([text(string.append(".", label))])
}

fn overwrite(label, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)

  [click(loc), classes([#("text-blue-700", True), ..highlight(target, alert)])]
  |> span([text(string.append(":=", label))])
}

fn tag(label, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)

  [click(loc), classes([#("text-blue-500", True), ..highlight(target, alert)])]
  |> span([text(label)])
}

fn match(label, _br, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)

  [click(loc), classes([#("text-blue-500", True), ..highlight(target, alert)])]
  |> span([text(label)])
}

fn perform(label, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)

  [click(loc), classes(highlight(target, alert))]
  |> span([span([class("text-gray-400")], [text("perform ")]), text(label)])
}

fn handle(label, loc, inferred) {
  let target = focused(loc)
  let alert = error(loc, inferred)

  [click(loc), classes(highlight(target, alert))]
  |> span([span([class("text-gray-400")], [text("handle ")]), text(label)])
}
