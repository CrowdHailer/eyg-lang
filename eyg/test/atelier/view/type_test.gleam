import atelier/view/typ
import eyg/analysis/typ as t
import gleeunit/should

pub fn shrink_test() -> Nil {
  typ.shrink(t.Fun(
    t.Unbound(101),
    t.Open(25),
    t.Record(t.Extend("foo", t.Unbound(101), t.Closed)),
  ))
  |> should.equal(t.Fun(
    t.Unbound(1),
    t.Open(0),
    t.Record(t.Extend("foo", t.Unbound(1), t.Closed)),
  ))
}
