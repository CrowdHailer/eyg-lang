import eyg/typer/monotype as t
import eyg/ast/pattern.{Pattern}

pub type Generator {
  Hole
  Env
  Format
  Loader
}

pub fn generator_to_string(generator) {
  case generator {
    Hole -> "Hole"
    Env -> "Env"
    Format -> "Format"
    Loader -> "Loader"
  }
}

pub fn generator_from_string(str) {
  case str {
    "Hole" -> Hole
    "Env" -> Env
    "Format" -> Format
    "Loader" -> Loader
  }
}

pub fn all_generators() {
  [Hole, Env, Format, Loader]
}

// provider implementations to not create loop
pub type Node(m) {
  Literal(internal: String)
  Binary(value: String)
  Tuple(elements: List(Expression(m)))
  Row(fields: List(#(String, Expression(m))))
  Variable(label: String)
  Let(pattern: Pattern, value: Expression(m), then: Expression(m))
  Function(pattern: Pattern, body: Expression(m))
  Call(function: Expression(m), with: Expression(m))
  Provider(config: String, generator: Generator)
}

pub type Expression(m) =
  #(m, Node(m))
