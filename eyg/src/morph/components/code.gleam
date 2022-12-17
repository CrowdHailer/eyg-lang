import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Some}
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

fn render_block(exp, br) {
  case exp {
    e.Let(_, _, _) -> {
      let br_inner = string.append(br, "  ")
      list.flatten([
        [text(string.append("{", br_inner))],
        render_text(exp, br_inner),
        [text(string.append(br, "}"))],
      ])
    }
    _ -> render_text(exp, br)
  }
}

pub fn render_text(exp, br) {
  case exp {
    e.Variable(var) -> [text(var)]
    e.Lambda(param, body) -> [
      text(param),
      text(" -> "),
      ..render_block(body, br)
    ]
    e.Apply(func, arg) ->
      list.flatten([
        render_text(func, br),
        [text("(")],
        render_text(arg, br),
        [text(")")],
      ])
    e.Let(label, value, then) ->
      list.flatten([
        [span([class("font-bold")], [text("let ")]), text(label), text(" = ")],
        render_block(value, br),
        [text(br)],
        render_text(then, br),
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
        False -> {
          let fields =
            fields
            |> list.map(fn(f) {
              [text(f.0), text(": "), ..render_text(f.1, br)]
            })
            |> list.intersperse([text(", ")])
            |> list.prepend([text("{")])
            |> list.append([[text("}")]])
            |> list.flatten
        }
      }
    e.Select(label) -> [text(string.append(".", label))]
    e.Tag(label) -> [span([class("text-blue-500")], [text(label)])]
    e.Match(options, else) -> {
      let br_inner = string.append(br, "  ")
      list.flatten([
        [span([class("font-bold")], [text("match")]), text(" {")],
        list.flatten(list.map(
          options,
          fn(opt) {
            let #(tag, var, then) = opt
            [
              text(br_inner),
              span([class("text-blue-500")], [text(tag)]),
              text("("),
              text(var),
              text(") -> "),
              ..render_block(then, br_inner)
            ]
          },
        )),
        case else {
          Some(#(var, then)) -> [
            text(br_inner),
            text(var),
            text(" -> "),
            ..render_block(then, br_inner)
          ]
          None -> []
        },
        [text(br), text("}")],
      ])
    }
    e.Perform(label) -> [
      span([class("font-bold")], [text("perform ")]),
      text(label),
    ]
    e.Deep(_, _) -> todo
  }
  // _ -> {
  //   io.debug(exp)
  //   [text("todo render")]
  // }
}
