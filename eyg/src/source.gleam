import gleam/option.{None}
import eygir/expression as e

// don't need helpers if just wire up edditor
// fn f(param, body) { 
//   e.Lambda(param, body)
//  }

const cli = e.Apply(
  e.Lambda("x", e.Record([#("foo", e.Variable("x"))], None)),
  e.Binary("hello"),
)

const web = e.Lambda(
  "req",
  e.Record([#("body", e.Binary("Hello, world!"))], None),
)

pub const source = e.Record([#("cli", e.Lambda("_", cli)), #("web", web)], None)
