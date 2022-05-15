import gleam/dynamic
import gleam/int
import gleam/list
import gleam/string
import eyg/typer/monotype as t
import eyg/ast/pattern.{Pattern} as p

pub type Generator {
  Type
  Env
  Example
  Format
  Loader
}

pub fn generator_to_string(generator) {
  case generator {
    Type -> "Type"
    Env -> "Env"
    Example -> "Example"
    Format -> "Format"
    Loader -> "Loader"
  }
}

pub fn generator_from_string(str) {
  case str {
    "Type" -> Type
    "Env" -> Env
    "Example" -> Example
    "Format" -> Format
    "Loader" -> Loader
  }
}

pub fn all_generators() {
  [Example, Env, Format, Loader, Type]
}

pub fn generate(generator, config, hole) {
  let generator = case generator {
    Example -> example
    Type -> lift_type
    Loader -> fn(_, _) { Ok(#(dynamic.from(Nil), Hole)) }
    _ -> fn(_, _) { Error(Nil) }
  }

  // Env -> env
  // Format -> format
  generator(config, hole)
}

pub fn example(config, hole) {
  case hole {
    t.Tuple(e) -> Ok(tuple_(list.map(e, fn(_) { binary(config) })))
    _ -> Error(Nil)
  }
}

pub fn lift_type(_config, hole) {
  case hole {
    t.Function(from, _to) -> {
      let inner = case from {
        t.Binary -> tagged("Binary", tuple_([]))
        t.Tuple(_) -> tagged("Tuple", tuple_([]))
        _ -> tagged("TODO", tuple_([]))
      }
      Ok(function(p.Variable(""), inner))
    }
    _ -> Error(Nil)
  }
}

// decide on load from env, i.e. call system. which makes constant folding hard
// OR we refer to map type and return a function
// We can generate stuff that assumes a scope and in the type checking works by pulling in the value.
// THis works best for JSON parsing etc. string in and eyg terms out
// fn env(_config, hole) {
//   case hole {
//     t.Record(fields, _) -> #(
//       Nil,
//       Record(list.map(
//         fields,
//         fn(field) {
//           case field {
//             #(name, t.Binary) -> #(name, #(Nil, Binary(name)))
//             #(name, _) -> #(name, #(Nil, Binary(name)))
//           }
//         },
//       )),
//     )
//   }
// }
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
// fn format(config, hole) {
//   case string.split(config, "%s") {
//     // warning why format if no stuff
//     [x] -> #(Nil, Function(p.Tuple([]), #(Nil, Binary(x))))
//     [start, ..parts] -> {
//       let #(array, args) = build_format(parts, [Binary(start)], [], 0)
//       #(
//         Nil,
//         Function(
//           p.Tuple(list.map(args, Some)),
//           #(Nil, Call(#(Nil, Variable("string.concat")), #(Nil, Tuple(array)))),
//         ),
//       )
//     }
//   }
//   // let parts = list.map(parts, Binary)
//   // let parts = list.intersperse(parts, Variable("r0"))
//   // let parts = list.map(parts, fn(x) { #(Nil, x) })
//   // #(
//   //   Nil,
//   //   Function(
//   //     p.Tuple([Some("r0")]),
//   //     #(
//   //       Nil,
//   //       Call(
//   //         #(Nil, Variable("String.prototype.concat.call")),
//   //         #(Nil, Tuple(parts)),
//   //       ),
//   //     ),
//   //   ),
//   // )
// }
// provider implementations to not create loop
pub type Node(m, g) {
  Binary(value: String)
  Tuple(elements: List(Expression(m, g)))
  Record(fields: List(#(String, Expression(m, g))))
  Access(value: Expression(m, g), label: String)
  Tagged(tag: String, value: Expression(m, g))
  Variable(label: String)
  Let(pattern: Pattern, value: Expression(m, g), then: Expression(m, g))
  Function(pattern: Pattern, body: Expression(m, g))
  Call(function: Expression(m, g), with: Expression(m, g))
  Case(
    value: Expression(m, g),
    branches: List(#(String, Pattern, Expression(m, g))),
  )
  Hole
  Provider(config: String, generator: Generator, generated: g)
}

pub type Expression(m, g) =
  #(m, Node(m, g))

pub fn binary(value) {
  #(dynamic.from(Nil), Binary(value))
}

pub fn call(function, with) {
  #(dynamic.from(Nil), Call(function, with))
}

pub fn function(for, body) {
  #(dynamic.from(Nil), Function(for, body))
}

pub fn let_(pattern, value, then) {
  #(dynamic.from(Nil), Let(pattern, value, then))
}

pub fn tuple_(elements) {
  #(dynamic.from(Nil), Tuple(elements))
}

pub fn variable(label) {
  #(dynamic.from(Nil), Variable(label))
}

pub fn record(fields) {
  #(dynamic.from(Nil), Record(fields))
}

pub fn access(value, label) {
  #(dynamic.from(Nil), Access(value, label))
}

pub fn tagged(tag, value) {
  #(dynamic.from(Nil), Tagged(tag, value))
}

pub fn case_(value, branches) {
  #(dynamic.from(Nil), Case(value, branches))
}

pub fn hole() {
  #(dynamic.from(Nil), Hole)
}
