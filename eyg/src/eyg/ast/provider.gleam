import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/string
import eyg/ast/expression as e
import eyg/typer/monotype as t
import eyg/ast/pattern as p

pub fn env_provider(_config, hole) {
  case hole {
    t.Row(fields, _) -> #(
      Nil,
      e.Row(list.map(
        fields,
        fn(field) {
          case field {
            #(name, t.Binary) -> #(name, #(Nil, e.Binary(name)))
            #(name, _) -> #(name, #(Nil, e.Binary(name)))
          }
        },
      )),
    )
  }
}

fn format(config, hole) {
  case string.split(config, "{0}") {
    [x] -> #(Nil, e.Function(p.Tuple([]), #(Nil, e.Binary(x))))
    parts -> {
      let parts = list.map(parts, e.Binary)
      let parts = list.intersperse(parts, e.Variable("r0"))
      let parts = list.map(parts, fn(x) { #(Nil, x) })
      // TODO use ast helpers but circular
      #(
        Nil,
        e.Function(
          p.Tuple([Some("r0")]),
          #(
            Nil,
            e.Call(
              #(Nil, e.Variable("String.prototype.concat.call")),
              #(Nil, e.Tuple(parts)),
            ),
          ),
        ),
      )
    }
  }
}
