import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import lustre/element.{button, div, p, pre, span, text}
import lustre/event.{dispatch, on_click}
import lustre/attribute.{class, classes, style}
import eygir/expression as e
import atelier/app.{SelectNode}

pub fn render(source, selection) {
  let loc = Location([], Some(selection))
  pre(
    [style([#("cursor", "pointer")]), class("w-full max-w-6xl")],
    do_render(source, "\n", loc),
  )
}

fn click(loc: Location) {
  on_click(dispatch(SelectNode(loc.path)))
}

// do we highlight whole line if lambda is in assigment
// deleting a call statement removes both sides, so needs to highlight both
// multiline values which are then applied
// call with multiline is weird, if multiline is not a fn
// let map = is -> f -> {}
// render_block keeps going untill new line
// let x = fn(a) { fn(b) { match { ... } }}
// let x = a -> b -> match { ... }
// multiline call
// foo(let x = ...)
// foo(
//   let x = 5
//   x
// )
// map(l)(x -> {
//    fpo
// })
// if collapsing border works with c or ml style syntax
//
// let x = y -> z -> {foo = x, y = z}(bob)
// let x = y -> (z -> {foo = x, y = z})(bob)
// let x = (y -> z -> {foo = x, y = z})(bob)
// let x = y z -> {}(foo)
// is x the thing being called or anon fn
// can't be x because of the then clause
// let x = y -> (z -> {})(foo)

pub fn do_render(exp, br, loc) {
  case exp {
    e.Variable(var) -> [variable(var, loc)]
    e.Lambda(param, body) -> [lambda(param, body, br, loc)]
    e.Apply(func, arg) -> call(func, arg, br, loc)
    e.Let(label, value, then) -> assigment(label, value, then, br, loc)
    e.Binary(value) -> [string(value, loc)]
    e.Integer(value) -> [integer(value, loc)]
    e.Vacant -> [vacant(loc)]
    e.Empty -> [text("{}")]
    e.Record(fields, from) ->
      case False {
        True -> [text("mul")]
        // TODO offset from from
        False -> {
          let fields =
            fields
            |> list.index_map(fn(i, f) {
              [text(f.0), text(": "), ..do_render(f.1, br, child(loc, i))]
            })
            |> list.intersperse([text(", ")])
            |> list.prepend([text("{")])
            |> list.append([[text("}")]])
            |> list.flatten
        }
      }
    e.Extend(label) -> [extend(label, loc)]
    e.Select(label) -> [select(label, loc)]
    e.Tag(label) -> [tag(label, loc)]
    e.Case(label) -> [match(label, br, loc)]
    e.NoCases -> [
      span(
        [
          class("text-gray-400"),
          click(loc),
          classes([#("text-gray-400", True), ..highlight(focused(loc))]),
        ],
        [text("nocases")],
      ),
    ]
    e.Match(branches, else) -> {
      let br_inner = string.append(br, "  ")
      list.flatten([
        [span([], [span([class("")], [text("match")]), text(" {")])],
        list.flatten(list.index_map(
          branches,
          fn(i, opt) {
            let #(tag, var, then) = opt
            [
              text(br_inner),
              span([class("text-blue-500")], [text(tag)]),
              text("("),
              text(var),
              text(") -> "),
              ..render_block(then, br_inner, child(loc, i))
            ]
          },
        )),
        case else {
          Some(#(var, then)) -> [
            text(br_inner),
            text(var),
            text(" -> "),
            ..render_block(then, br_inner, child(loc, list.length(branches)))
          ]
          None -> []
        },
        [text(br), text("}")],
      ])
    }
    e.Perform(label) -> [perform(label, loc)]
    e.Deep(_, _) -> todo
  }
}

// select the whole thing can be border if it is collapsed
// need a single line view for each expression, then we can select a let by collapsing
// background, underline
// TODO save
// TODO handle needing brackets for functions as args
// TODO handle not creating new arrows fo fn's
// fn render arg wrap if need be etc
// fn render call'd etc
fn render_block(exp, br, loc) {
  // TODO pretty sure need to move indented BR up but not for closing
  case exp {
    e.Let(_, _, _) ->
      case open(loc) {
        True -> {
          let br_inner = string.append(br, "  ")
          list.flatten([
            [text(string.append("{", br_inner))],
            do_render(exp, br_inner, loc),
            [text(string.append(br, "}"))],
          ])
        }
        False -> [span([click(loc)], [text("{ ... }")])]
      }
    _ -> do_render(exp, br, loc)
  }
}

fn highlight(target) {
  [#("border-b-2", target), #("border-indigo-300", True)]
}

fn variable(var, loc) {
  let target = focused(loc)
  [classes(highlight(target)), click(loc)]
  |> span([text(var)])
}

fn lambda(param, body, br, loc) {
  let target = focused(loc)

  [classes(highlight(target))]
  |> span([
    span([click(loc)], [text(param), text(" -> ")]),
    ..render_block(body, br, child(loc, 0))
  ])
}

fn render_branch(label, then, else, br, loc_branch, loc_else) {
  let loc_match = child(loc_branch, 0)
  let loc_then = child(loc_branch, 1)
  let match =
    [
      click(loc_match),
      classes([#("text-blue-500", True), ..highlight(focused(loc_match))]),
    ]
    |> span([text(label)])
  let branch = render_block(then, br, loc_then)
  [
    text(br),
    span(
      [classes(highlight(focused(loc_branch)))],
      [match, text(" "), ..branch],
    ),
    ..case else {
      e.NoCases -> [
        text(br),
        span([class("text-gray-400"), click(loc_else)], [text("-- closed --")]),
      ]
      e.Apply(e.Apply(e.Case(label), then), else) ->
        render_branch(
          label,
          then,
          else,
          br,
          child(loc_else, 0),
          child(loc_else, 1),
        )
      _ -> [text(br), ..do_render(else, br, loc_else)]
    }
  ]
}

// case can only be applied with literal or var to correct things
// call with binary is error
// apply to just a case could leave it as ++
// nocases should be rendered alone as empty match
fn call(func, arg, br, loc) {
  let target = focused(loc)
  // not target but any selected
  let inner = case func {
    // e.Apply(e.Case(label), then) -> {
    //   let loc_branch = child(loc, 0)
    //   let loc_else = child(loc, 1)
    //   case open(loc_branch) || open(loc_else) {
    //     True -> {
    //       let pre = [
    //         span(
    //           [click(loc)],
    //           [span([class("text-gray-400")], [text("match")]), text(" {")],
    //         ),
    //       ]
    //       let branches =
    //         render_branch(
    //           label,
    //           then,
    //           arg,
    //           string.append(br, "  "),
    //           loc_branch,
    //           loc_else,
    //         )
    //       let post = [text(br), text("}")]
    //       list.flatten([pre, branches, post])
    //     }
    //     False -> [
    //       span(
    //         [click(loc_branch)],
    //         [span([class("text-gray-400")], [text("match")]), text(" { ... }")],
    //       ),
    //     ]
    //   }
    // }
    _ ->
      // arg becomes then
      list.flatten([
        render_block(func, br, child(loc, 0)),
        [text("(")],
        render_block(arg, br, child(loc, 1)),
        [text(")")],
      ])
  }

  [span([classes(highlight(target))], inner)]
}

fn assigment(label, value, then, br, loc) {
  let active = focused(loc)
  let assignment = [
    span(
      [click(loc)],
      [span([class("text-gray-400")], [text("let ")]), text(label), text(" = ")],
    ),
    ..render_block(value, br, child(loc, 0))
  ]
  let el = span([classes(highlight(active))], assignment)
  [el, text(br), ..do_render(then, br, child(loc, 1))]
}

fn string(value, loc) {
  let target = focused(loc)
  let content = string.concat(["\"", value, "\""])
  [click(loc), classes([#("text-green-500", True), ..highlight(target)])]
  |> span([text(content)])
}

fn integer(value, loc) {
  let target = focused(loc)
  [click(loc), classes([#("text-purple-500", True), ..highlight(target)])]
  |> span([text(int.to_string(value))])
}

fn vacant(loc) {
  let target = focused(loc)
  [click(loc), classes([#("text-red-500", True), ..highlight(target)])]
  |> span([text("todo")])
}

fn extend(label, loc) {
  let target = focused(loc)
  [click(loc), classes(highlight(target))]
  |> span([text(string.append("+", label))])
}

fn select(label, loc) {
  let target = focused(loc)
  [click(loc), classes(highlight(target))]
  |> span([text(string.append(".", label))])
}

fn tag(label, loc) {
  let target = focused(loc)
  [click(loc), classes([#("text-blue-500", True), ..highlight(target)])]
  |> span([text(label)])
}

fn match(label, br, loc) {
  let target = focused(loc)
  [click(loc), classes([#("text-blue-500", True), ..highlight(target)])]
  |> span([text(label)])
}

fn perform(label, loc) {
  let target = focused(loc)
  [click(loc), classes(highlight(target))]
  |> span([span([class("text-gray-400")], [text("perform ")]), text(label)])
}

// location is separate to path, extract but it may be view layer only.
pub type Location {
  Location(path: List(Int), selection: Option(List(Int)))
}

fn open(location) {
  let Location(selection: selection, ..) = location
  case selection {
    None -> False
    Some(_) -> True
  }
}

fn focused(location) {
  let Location(selection: selection, ..) = location
  case selection {
    Some([]) -> True
    _ -> False
  }
}

// call location.step
fn child(location, i) {
  let Location(path: path, selection: selection) = location
  let path = list.append(path, [i])
  let selection = case selection {
    Some([j, ..inner]) if i == j -> Some(inner)
    _ -> None
  }
  Location(path, selection)
}
