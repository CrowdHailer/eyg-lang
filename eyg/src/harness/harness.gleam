import gleam/option.{None}
import eyg/typer/monotype as t
import eyg/typer/polytype

pub fn string() {
  polytype.Polytype(
    [1, 2, 3],
    t.Row(
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
        #("debug", t.Function(t.Unbound(2), t.Unbound(2))),
        #("parse_int", t.Function(t.Binary, t.Native("Integer"))),
        #(
          "add",
          t.Function(
            t.Tuple([t.Native("Integer"), t.Native("Integer")]),
            t.Native("Integer"),
          ),
        ),
        #(
          "compare",
          t.Function(
            t.Tuple([t.Native("Integer"), t.Native("Integer")]),
            t.Function(
              t.Row(
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
      ],
      None,
    ),
  )
}

pub fn foo() -> Nil {
  #(5)
  Nil
}
