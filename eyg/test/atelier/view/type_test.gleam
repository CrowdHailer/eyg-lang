import eyg/analysis/typ as t
import atelier/view/typ
import gleeunit/should

pub fn shrink_test() -> Nil {
  typ.shrink(t.Fun(
    t.Unbound(101),
    t.Open(25),
    t.Record(t.Extend("foo", t.Unbound(101), t.Closed)),
  ))
  |> should.equal(t.Fun(
    t.Unbound(0),
    t.Open(1),
    t.Record(t.Extend("foo", t.Unbound(0), t.Closed)),
  ))
}
