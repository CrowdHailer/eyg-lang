import gleam/option.{None, Some}
import eygir/expression as e

const cli = e.Lambda(
  "_",
  e.Let(
    "_",
    e.Apply(e.Perform("Log"), e.Binary("Hello Logger")),
    e.Apply(e.Apply(e.Extend("eff"), e.Variable("_")), e.Empty),
  ),
)

const web = e.Lambda(
  "req",
  e.Let(
    "response",
    e.Apply(
      e.Apply(
        e.Extend("body"),
        e.Apply(
          e.Apply(e.Variable("string_append"), e.Binary("hello")),
          e.Variable("req"),
        ),
      ),
      e.Empty,
    ),
    e.Let(
      "match",
      e.Apply(
        e.Apply(
          e.Case("True"),
          e.Lambda(
            "_",
            e.Apply(e.Apply(e.Extend("body"), e.Binary("special")), e.Empty),
          ),
        ),
        e.Apply(
          e.Apply(e.Case("False"), e.Lambda("_", e.Variable("response"))),
          e.NoCases,
        ),
      ),
      e.Apply(
        e.Variable("match"),
        e.Apply(
          e.Apply(e.Variable("equal"), e.Binary("/foo")),
          e.Variable("req"),
        ),
      ),
    ),
  ),
)

pub const source = e.Let(
  "cli",
  cli,
  e.Let(
    "web",
    web,
    e.Apply(
      e.Apply(e.Extend("cli"), e.Variable("cli")),
      e.Apply(e.Apply(e.Extend("web"), e.Variable("web")), e.Empty),
    ),
  ),
)
