import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import lustre/element.{button, div, p, span, text}
import lustre/attribute.{class}
import eygir/expression as e

pub fn render(source) {
  div([class("cover")], [div([], [text("code")]), expression(source)])
}

// lists of expressions collapse on spans
// apply appply apply 
// fn fn fn fn
fn expression(exp) {
  case exp {
    e.Variable(label) -> text("var")
    e.Lambda(param, body) -> {
      // text("lambda")
      let singular = span([], [text(param), text(" -> "), expression(body)])
    }
    e.Apply(func, arg) -> {
      text("func")
      let single = span([], [expression(func), expression(arg)])
    }
    e.Let(label, value, then) -> text("Let")
    e.Integer(value) ->
      span([class("text-green-400")], [text(int.to_string(value))])
    e.Binary(value) ->
      span(
        [class("text-green-400")],
        [text(string.concat(["\"", value, "\""]))],
      )
    e.Vacant -> span([class("text-ref-400")], [text("todo")])
    e.Record(fields, from) ->
      div(
        [class("hstack")],
        [
          div([class("bg-green-500")], [text("")]),
          div(
            [],
            [
              div([], [span([], [text("{")])]),
              div(
                [],
                [
                  span([], [text("}")]),
                  ..list.map(
                    fields,
                    fn(field) {
                      let #(label, exp) = field
                      expression(exp)
                    },
                  )
                ],
              ),
            ],
          ),
        ],
      )
    e.Select(label) -> text("select")
    e.Tag(label) -> text("tag")
    e.Match(_, _) -> text("match")
    e.Perform(label) -> text("perform")
    e.Deep(_, _) -> text("handler")
  }
}

fn multiline(exp) {
  io.debug(exp)
  case exp {
    e.Variable(_) -> False
    e.Lambda(_, body) -> multiline(body)
    e.Apply(func, arg) -> multiline(func) || multiline(arg)
    e.Let(_, _, _) -> True
    e.Integer(_) | e.Binary(_) | e.Vacant -> False
    e.Record(fields, _) ->
      list.length(fields) > 3 || list.any(fields, fn(f) { multiline(f.1) })
    e.Select(_) | e.Tag(_) | e.Perform(_) -> False
    e.Match(_, _) | e.Deep(_, _) -> True
  }
  |> io.debug
}

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

// loc is inner position but if block
fn render_block(exp, br, loc, index) {
  case exp {
    e.Let(_, _, _) ->
      case open(loc) {
        True -> {
          let class = case focused(loc) {
            True -> class("font-bold")
            False -> class("")
          }
          let br_inner = string.append(br, "  ")
          list.flatten([
            [span([class], [text(string.append("{", br_inner))])],
            render_text(exp, br_inner, child(loc, index)),
            [span([class], [text(string.append(br, "}"))])],
          ])
        }
        False -> [text("{ ... }")]
      }
    _ -> render_text(exp, br, child(loc, index))
  }
}

fn active(children, loc) {
  let class = case focused(loc) {
    True -> class("font-bold")
    False -> class("")
  }
  span([class], children)
}

pub fn render_text(exp, br, loc) {
  case exp {
    e.Variable(var) -> [text(var)]
    e.Lambda(param, body) -> [
      text(param),
      text(" -> "),
      ..render_block(body, br, loc, 1)
    ]
    e.Apply(func, arg) ->
      list.flatten([
        render_text(func, br, child(loc, 0)),
        [text("(")],
        render_text(arg, br, child(loc, 1)),
        [text(")")],
      ])
    e.Let(label, value, then) ->
      list.flatten([
        [
          active(
            [
              span([class(" text-gray-400")], [text("let ")]),
              text(label),
              text(" = "),
            ],
            loc,
          ),
        ],
        render_block(value, br, loc, 1),
        [text(br)],
        render_text(then, br, child(loc, 2)),
      ])

    // Dont space around records
    // e.Record([], None) -> [text("{}")]
    e.Binary(value) -> [
      span([class("text-green-500")], [text("\""), text(value), text("\"")]),
    ]
    e.Integer(value) -> [
      span([class("text-purple-500")], [text(int.to_string(value))]),
    ]
    e.Vacant -> [span([class("text-red-500")], [text("todo")])]
    e.Record(fields, from) ->
      case
        list.any(fields, fn(f) { multiline(f.1) })
        |> io.debug()
      {
        True -> [text("mul")]
        // TODO offset from from
        False -> {
          let fields =
            fields
            |> list.index_map(fn(i, f) {
              [text(f.0), text(": "), ..render_text(f.1, br, child(loc, i))]
            })
            |> list.intersperse([text(", ")])
            |> list.prepend([text("{")])
            |> list.append([[text("}")]])
            |> list.flatten
        }
      }
    e.Select(label) -> [text(string.append(".", label))]
    e.Tag(label) -> [span([class("text-blue-500")], [text(label)])]
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
              ..render_block(then, br_inner, loc, i)
            ]
          },
        )),
        case else {
          Some(#(var, then)) -> [
            text(br_inner),
            text(var),
            text(" -> "),
            ..render_block(then, br_inner, loc, list.length(branches))
          ]
          None -> []
        },
        [text(br), text("}")],
      ])
    }
    e.Perform(label) -> [
      span([class(" text-gray-400")], [text("perform ")]),
      text(label),
    ]
    e.Deep(_, _) -> todo
  }
}
// select the whole thing can be border if it is collapsed
// need a single line view for each expression, then we can select a let by collapsing
// selecting the
// let a = |x -> { ... }|
// TODO focused, click, move, transform
// background, underline
// TODO save 