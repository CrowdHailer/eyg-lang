import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import eyg/typer/monotype as t
import eyg/ast/pattern.{Pattern} as p

pub type Generator {
  Hole
  Env
  Example
  Format
  Loader
}

pub fn generator_to_string(generator) {
  case generator {
    Hole -> "Hole"
    Env -> "Env"
    Example -> "Example"
    Format -> "Format"
    Loader -> "Loader"
  }
}

pub fn generator_from_string(str) {
  case str {
    "Hole" -> Hole
    "Env" -> Env
    "Example" -> Example
    "Format" -> Format
    "Loader" -> Loader
  }
}

pub fn all_generators() {
  [Example, Env, Format, Loader]
}

pub fn generate(generator, config, hole) {
  let generator = case generator {
    Example -> example
    Env -> env
    Format -> format
    // TODO this should do better for loading
    _ -> fn(_, _) { #(Nil, Provider("", Hole, Nil)) }
  }
  generator(config, hole)
}

pub fn example(config, hole) {
  case hole {
    t.Tuple(e) -> tuple_(list.map(e, fn(_) { binary(config) }))
  }
  // _
}

// decide on load from env, i.e. call system. which makes constant folding hard
// OR we refer to map type and return a function
// We can generate stuff that assumes a scope and in the type checking works by pulling in the value.
// THis works best for JSON parsing etc. string in and eyg terms out
fn env(_config, hole) {
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

fn build_format(remaining, acc, args, i) {
  case remaining {
    [] -> #(
      list.reverse(acc)
      |> list.map(fn(x) { #(Nil, x) }),
      list.reverse(args),
    )
    [part, ..rest] -> {
      // let arg = string.concat("s", int.to_string(i))
      // The render takes care of making it unique
      let arg = "s"
      build_format(
        rest,
        [Binary(part), Variable(arg), ..acc],
        [arg, ..args],
        i + 1,
      )
    }
  }
}

// Ask how do you pass in the functions for the compiled code in Elixir
fn format(config, hole) {
  case string.split(config, "%s") {
    // warning why format if no stuff
    [x] -> #(Nil, Function(p.Tuple([]), #(Nil, Binary(x))))
    [start, ..parts] -> {
      let #(array, args) = build_format(parts, [Binary(start)], [], 0)
      #(
        Nil,
        Function(
          p.Tuple(list.map(args, Some)),
          #(Nil, Call(#(Nil, Variable("string.concat")), #(Nil, Tuple(array)))),
        ),
      )
    }
  }
  // let parts = list.map(parts, Binary)
  // let parts = list.intersperse(parts, Variable("r0"))
  // let parts = list.map(parts, fn(x) { #(Nil, x) })
  // // TODO use ast helpers but circular
  // #(
  //   Nil,
  //   Function(
  //     p.Tuple([Some("r0")]),
  //     #(
  //       Nil,
  //       Call(
  //         #(Nil, Variable("String.prototype.concat.call")),
  //         #(Nil, Tuple(parts)),
  //       ),
  //     ),
  //   ),
  // )
}

// provider implementations to not create loop
pub type Node(m, g) {
  Literal(internal: String)
  Binary(value: String)
  Tuple(elements: List(Expression(m, g)))
  Row(fields: List(#(String, Expression(m, g))))
  Variable(label: String)
  Let(pattern: Pattern, value: Expression(m, g), then: Expression(m, g))
  Function(pattern: Pattern, body: Expression(m, g))
  Call(function: Expression(m, g), with: Expression(m, g))
  Provider(config: String, generator: Generator, generated: g)
}

pub type Expression(m, g) =
  #(m, Node(m, g))

pub fn binary(value) {
  #(Nil, Binary(value))
}

pub fn call(function, with) {
  #(Nil, Call(function, with))
}

pub fn function(for, body) {
  #(Nil, Function(for, body))
}

pub fn let_(pattern, value, then) {
  #(Nil, Let(pattern, value, then))
}

pub fn tuple_(elements) {
  #(Nil, Tuple(elements))
}
