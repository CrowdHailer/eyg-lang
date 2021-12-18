import gleam/option.{None}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn string() {
  polytype.Polytype(
    [1],
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
                  monotype.Tuple([monotype.Binary, monotype.Unbound(999)]),
                  monotype.Unbound(1),
                ),
              ]),
              monotype.Unbound(1),
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
