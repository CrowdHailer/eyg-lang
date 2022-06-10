//  What does Roc call program + platform -> Application
// Does program space workspace things like tests live there
// browser.compile browser.harness
import gleam/option.{None, Some}
// typer.common
import eyg/typer
import eyg/typer/monotype as t
import eyg/typer/polytype
import eyg/typer/harness

pub type Browser {
  Integer
  Array(t.Monotype(Browser))
}

pub fn native_to_string(type_) {
  case type_ {
    Integer -> "Integer"
    _ -> todo("more")
  }
}

pub fn harness() {
  harness.Harness(
    [#("equal", typer.equal_fn()), #("harness", string())],
    native_to_string,
  )
}

// fn p0() {
// }
// Polytimes are always instantiated we can reduce to lowest number when put in scope
// perhaps they should be letters or similar
pub fn string() {
  polytype.Polytype(
    [1, 2, 3, 4, 5],
    t.Record(
      [
        #(
          "split",
          t.Function(
            t.Tuple([t.Binary, t.Binary]),
            t.Function(
              t.Tuple([
                t.Function(t.Tuple([]), t.Unbound(1)),
                t.Function(
                  // TODO need recursive type definition
                  t.Tuple([t.Binary, t.Unbound(999)]),
                  t.Unbound(1),
                ),
              ]),
              t.Unbound(1),
            ),
          ),
        ),
        #("concat", t.Function(t.Tuple([t.Binary, t.Binary]), t.Binary)),
        #("debug", t.Function(t.Unbound(2), t.Unbound(2))),
        #("parse_int", t.Function(t.Binary, t.Native(Integer))),
        #(
          "add",
          t.Function(
            t.Tuple([t.Native(Integer), t.Native(Integer)]),
            t.Native(Integer),
          ),
        ),
        #(
          "compare",
          t.Function(
            t.Tuple([t.Native(Integer), t.Native(Integer)]),
            t.Function(
              t.Record(
                [
                  #("Lt", t.Function(t.Tuple([]), t.Unbound(3))),
                  #("Eq", t.Function(t.Tuple([]), t.Unbound(3))),
                  #("Gt", t.Function(t.Tuple([]), t.Unbound(3))),
                ],
                None,
              ),
              t.Unbound(3),
            ),
          ),
        ),
        #(
          "compile",
          t.Function(
            t.Tuple([t.Binary, t.Binary]),
            t.Union([#("OK", t.Unbound(4)), #("Error", t.Binary)], Some(5)),
          ),
        ),
        #("source", t.Function(t.Tuple([]), t.Binary)),
      ],
      None,
    ),
  )
}
