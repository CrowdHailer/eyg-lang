import eyg/ir/tree as ir
import morph/editable as e
import morph/navigation
import morph/projection as p

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
