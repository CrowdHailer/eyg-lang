import gleam/io
import gleam/list
import gleam/string
import eyg/ast/expression.{
  Binary, Call, Function, Let, Node, Provider, Row, Tuple, Variable,
}
import eyg/typer/monotype as t
import eyg/ast/pattern

fn env_provider(_config, hole) {
  case hole {
    t.Row(fields, _) -> #(
      Nil,
      Row(list.map(
        fields,
        fn(field) {
          case field {
            #(name, t.Binary) -> #(name, #(Nil, Binary(name)))
            #(name, _) -> #(name, #(Nil, Binary(name)))
          }
        },
      )),
    )
  }
}

fn format(config, hole) {
  case string.split(config, "{0}") {
    [x] -> #(
      Nil,
      Function(
        "$",
        #(Nil, Let(pattern.Tuple([]), #(Nil, Variable("$")), #(Nil, Binary(x)))),
      ),
    )
    parts -> {
      let parts = list.map(parts, Binary)
      let parts = list.intersperse(parts, Variable("r0"))
      let parts = list.map(parts, fn(x) { #(Nil, x) })
      #(
        Nil,
        Function(
          "$",
          #(
            Nil,
            Let(
              pattern.Tuple(["r0"]),
              #(Nil, Variable("$")),
              #(
                Nil,
                Call(
                  #(Nil, Variable("String.prototype.concat.call")),
                  #(Nil, Tuple(parts)),
                ),
              ),
            ),
          ),
        ),
      )
    }
  }
}

pub fn from_name(name) {
  case name {
    "format" -> #(Nil, Provider("", format))
    "env" | _ -> #(Nil, Provider("", env_provider))
  }
}
