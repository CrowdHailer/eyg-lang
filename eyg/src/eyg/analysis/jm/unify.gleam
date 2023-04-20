import gleam/io
import gleam/map
import eyg/analysis/jm/type_ as t

pub fn unify(t1, t2, s)  {
    do_unify([#(t1, t2)], s)   
}

// s is a function from var -> t
fn do_unify(constraints, s)  {
  // Have to try and substitute at every point because new substitutions can come into existance
  case constraints {
    [] -> Ok(s)
    [#(t.Var(i), t.Var(infer)), ..constraints] -> do_unify(constraints, s)
    [#(t.Var(i), t1), ..constraints] | [#(t1, t.Var(i)), ..constraints] -> case map.get(s, i) {
      Ok(t2) -> do_unify([#(t1, t2),..constraints], s) 
      Error(Nil) -> do_unify(constraints, map.insert(s, i, t1))
    }
    [#(t.Fun(a1, e1, r1), t.Fun(a2, e2, r2)), ..cs] -> do_unify([#(a1, a2), #(e1, e2), #(r1, r2), ..cs], s)
    [#(t.LinkedList(i1), t.LinkedList(i2)), ..cs] -> do_unify([#(i1, i2), ..cs], s)
    _ -> {
      io.debug("I think this ods it")
      io.debug(constraints)
      todo("I need to handle records")
      Error(Nil)
      }
  }
}