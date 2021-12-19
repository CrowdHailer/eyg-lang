import gleam/option.{None}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn string() {
  polytype.Polytype(
    [1, 2],
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
        #("parse_int", monotype.Function(monotype.Binary, monotype.Tuple([]))),
      ],
      None,
    ),
  )
}

pub fn foo() -> Nil {
  #(5)
  Nil
}
