import gleam/io
import gleam/option.{None}
import eyg/typer/polytype
import eyg/typer/monotype as t

pub fn difference_test() {
  assert [] = polytype.difference([], [])
  assert [] = polytype.difference([1], [1])
  assert [] = polytype.difference([1, 2], [2, 1])

  assert [1] = polytype.difference([1], [])
  assert [1, 2, 3] = polytype.difference([1, 2, 3], [])
  assert [1, 3] = polytype.difference([1, 2, 3], [2])
}

pub fn generalizing_a_record_test() {
  let resolved =
    t.Record(
      fields: [
        #(
          "id",
          t.Function(
            from: t.Unbound(i: 2),
            to: t.Unbound(i: 2),
            effects: t.Unbound(i: 4),
          ),
        ),
      ],
      extra: None,
    )
  let polytype = polytype.generalise(resolved, [])
  assert [4, 2] = polytype.forall
}
