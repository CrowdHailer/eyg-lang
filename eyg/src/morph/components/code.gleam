import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import lustre/element.{button, div, p, span, text}
import lustre/event.{dispatch, on_click}
import lustre/attribute.{class}
import eygir/expression as e
import atelier/app.{SelectNode}

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
    _ -> todo("old")
  }
}

fn multiline(exp) {
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
    _ -> todo("old")
  }
}
// let map result then =
//   (case(Ok)(v -> Ok(then(v)))
//   case(Error)(_ -> result))(result)
