import eyg/ir/tree as ir
import gleam/list
import morph/editable as e
import morph/navigation
import morph/projection as p
import morph/reference

pub fn no_next_vacant_test() {
  assert Error(Nil)
    == ir.let_("x", ir.integer(12), ir.string("x"))
    |> e.from_annotated()
    |> navigation.first()
    |> navigation.next_vacant()
}

pub fn nex_vacant_test() {
  assert Ok(#(p.Exp(e.Vacant), [p.BlockTail([#(e.Bind("x"), e.Integer(12))])]))
    == ir.let_("x", ir.integer(12), ir.vacant())
    |> e.from_annotated()
    |> navigation.first()
    |> navigation.next_vacant()
}

pub fn explicit_references_are_navigation_leaves_test() {
  reference.all()
  |> list.each(fn(reference) {
    let expression = e.Reference(reference)
    let projection = #(p.Exp(expression), [])
    assert projection == navigation.first(expression)
    assert projection == navigation.next(projection)
    assert projection == navigation.previous(projection)
  })
}
