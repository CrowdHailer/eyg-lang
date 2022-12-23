import gleam/option.{None, Some}
import eygir/expression as e

const cli = e.Apply(
  e.Lambda("x", e.Record([#("foo", e.Variable("x"))], None)),
  e.Binary("hello"),
)

const web = e.Lambda(
  "req",
  e.Let(
    "response",
    e.Apply(e.Apply(e.Extend("body"), e.Binary("Hello, world!")), e.Empty),
    e.Let(
      "_",
      e.Apply(e.Select("body"), e.Variable("response")),
      e.Let(
        "return",
        e.Apply(
          e.Apply(
            e.Apply(e.Case("Some"), e.Lambda("x", e.Variable("x"))),
            e.Apply(
              e.Apply(e.Case("None"), e.Lambda("_", e.Binary("other"))),
              e.NoCases,
            ),
          ),
          e.Variable("thing"),
        ),
        e.Variable("response"),
      ),
    ),
  ),
)

pub const source = e.Let(
  "pre",
  e.Binary("other"),
  e.Let(
    "web",
    web,
    e.Record([#("cli", e.Lambda("_", cli)), #("web", e.Variable("web"))], None),
  ),
)
