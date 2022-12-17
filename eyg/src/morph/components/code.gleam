import gleam/int
import gleam/list
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
