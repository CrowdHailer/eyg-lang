import gleam/option.{None}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn string() {
  polytype.Polytype(
    [1, 2, 3],
    monotype.Row(
      [
        #(
          "split",
          monotype.Function(
            monotype.Tuple([monotype.Binary, monotype.Binary]),
            monotype.Function(
              monotype.Tuple([
                monotype.Function(monotype.Tuple([]), monotype.Unbound(1)),
                monotype.Function(
                  // TODO need recursive type definition
                  monotype.Tuple([monotype.Binary, monotype.Unbound(999)]),
                  monotype.Unbound(1),
                ),
              ]),
              monotype.Unbound(1),
            ),
          ),
        ),
        #("debug", monotype.Function(monotype.Unbound(2), monotype.Unbound(2))),
        #("parse_int", monotype.Function(monotype.Binary, monotype.Integer)),
        #(
          "add",
          monotype.Function(
            monotype.Tuple([monotype.Integer, monotype.Integer]),
            monotype.Integer,
          ),
        ),
        #(
          "compare",
          monotype.Function(
            monotype.Tuple([monotype.Integer, monotype.Integer]),
            monotype.Function(
              monotype.Row(
                [
                  #(
                    "Lt",
                    monotype.Function(monotype.Tuple([]), monotype.Unbound(3)),
                  ),
                  #(
                    "Eq",
                    monotype.Function(monotype.Tuple([]), monotype.Unbound(3)),
                  ),
                  #(
                    "Gt",
                    monotype.Function(monotype.Tuple([]), monotype.Unbound(3)),
                  ),
                ],
                None,
              ),
              monotype.Unbound(3),
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
