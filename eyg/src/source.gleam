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
          e.Apply(e.Tag("Some"), e.Binary("foo")),
        ),
        e.Variable("response"),
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
