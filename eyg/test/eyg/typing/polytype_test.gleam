import gleam/io
import gleam/option.{None, Some}
import eyg/typer/polytype
import eyg/typer/monotype as t

// This test was from a specific bug, delete and extend the polytype tests as needed
pub fn generalising_recusive_function_test() {
  let resolved =
    t.Function(
      from: t.Tuple(elements: [
        t.Recursive(
          i: 3,
          type_: t.Union(
            variants: [
              #("Nil", t.Tuple(elements: [])),
              #("Cons", t.Tuple(elements: [t.Unbound(i: 7), t.Unbound(i: 3)])),
            ],
            extra: None,
          ),
        ),
        t.Function(
          from: t.Unbound(i: 7),
          to: t.Union(
            variants: [
              #("False", t.Tuple(elements: [])),
              #("True", t.Tuple(elements: [])),
            ],
            extra: None,
          ),
          effects: t.Unbound(i: 6),
        ),
      ]),
      to: t.Union(
        variants: [#("Error", t.Tuple(elements: [])), #("Ok", t.Unbound(i: 7))],
        extra: Some(17),
      ),
      effects: t.Unbound(i: 6),
    )
  let polytype = polytype.generalise(resolved, [])
  assert [17, 6, 7] = polytype.forall
}

pub fn difference_test()  {
    assert [] = polytype.difference([], [])
    assert [] = polytype.difference([1], [1])
    assert [] = polytype.difference([1, 2], [2, 1])

    assert [1] = polytype.difference([1], [])
    assert [1, 2, 3] = polytype.difference([1, 2, 3], [])
    assert [1, 3] = polytype.difference([1, 2, 3], [2])
}

pub fn generalizing_a_record_test()  {
    let resolved = t.Record(fields: [#("id", t.Function(from: t.Unbound(i: 2), to: t.Unbound(i: 2), effects: t.Unbound(i: 4)))], extra: None)
    let polytype = polytype.generalise(resolved, [])
    assert [4, 2] = polytype.forall
}