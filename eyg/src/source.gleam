import gleam/option.{None, Some}
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

const pre = e.Let(
  "x",
  e.Integer(5),
  e.Let(
    "y",
    e.Binary("foo"),
    e.Let(
      "z",
      e.Match(
        [
          #("Foo", "_", e.Let("tmp", e.Variable("user"), e.Tag("Noop"))),
          #(
            "Nee",
            "parts",
            e.Apply(e.Apply(e.Select("map"), e.Variable("list")), e.Tag("Some")),
          ),
          #("Bar", "_", e.Apply(e.Select("bob"), e.Variable("xxx"))),
        ],
        Some(#("else", e.Apply(e.Tag("Ok"), e.Binary("fallback")))),
      ),
      e.Let(
        "fizz",
        e.Lambda("y", e.Lambda("z", e.Let("x", e.Variable("y"), e.Vacant))),
        e.Apply(e.Perform("log"), e.Binary("message")),
      ),
    ),
  ),
)

pub const source = e.Let(
  "pre",
  pre,
  e.Record([#("cli", e.Lambda("_", cli)), #("web", web)], None),
)
