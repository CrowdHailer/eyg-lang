import gleam/list
import eyg/ast/expression.{Node, Row, Binary}
import eyg/typer/monotype as t

fn env_provider(_config, hole) {
  case hole {
    t.Row(fields, _) ->
      #(Nil, Row(list.map(
        fields,
        fn(field) {
          case field {
            #(name, t.Binary) -> #(name, #(Nil, Binary(name)))
            #(name, _) -> #(name, #(Nil, Binary(name)))
          }
        },
      )))
  }
}
