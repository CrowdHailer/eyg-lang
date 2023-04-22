import gleam/io
import gleam/map
import gleam/result
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/error

pub fn unify(t1, t2, s, next)  {
  do_unify([#(t1, t2)], s, next)   
}
// I dont think this is the same as described because we don't keep lookup to original i.
// s is a function from var -> t
fn do_unify(constraints, s, next)  {
  // Have to try and substitute at every point because new substitutions can come into existance
  case constraints {
    [] -> Ok(#(s, next))
    [#(t.Var(i), t.Var(j)), ..constraints] if i == j -> do_unify(constraints, s, next)
    // TODO varbind occurs in
    [#(t.Var(i), t1), ..constraints] | [#(t1, t.Var(i)), ..constraints] -> case map.get(s, i) {
      Ok(t2) -> do_unify([#(t1, t2),..constraints], s, next) 
      Error(Nil) -> do_unify(constraints, map.insert(s, i, t1), next)
    }
    [#(t.Fun(a1, e1, r1), t.Fun(a2, e2, r2)), ..cs] -> do_unify([#(a1, a2), #(e1, e2), #(r1, r2), ..cs], s, next)
    [#(t.Integer, t.Integer), ..cs] -> do_unify(cs, s, next)
    [#(t.String, t.String), ..cs] -> do_unify(cs, s, next)
    [#(t.LinkedList(i1), t.LinkedList(i2)), ..cs] -> do_unify([#(i1, i2), ..cs], s, next)
    [#(t.Record(r1), t.Record(r2)), ..cs] -> do_unify([#(r1, r2), ..cs], s, next)
    [#(t.Union(r1), t.Union(r2)), ..cs] -> do_unify([#(r1, r2), ..cs], s, next)
    [#(t.Empty, t.Empty), ..cs] -> do_unify(cs, s, next)
    [#(t.RowExtend(label1, value1, tail1), t.RowExtend(_,_,_) as row2), ..cs] -> {
      use #(value2, tail2, s, next) <- result.then(rewrite_row(label1, row2, s, next))
      do_unify([#(value1, value2), #(tail1, tail2), ..cs], s, next)
    }
    [#(t.EffectExtend(label1, #(lift1, reply1), tail1), t.EffectExtend(_,_,_) as row2), ..cs] -> {
      use #(lift2, reply2, tail2, s, next) <- result.then(rewrite_effect(label1, row2, s, next))
      do_unify([#(lift1, lift2), #(reply1, reply2), #(tail1, tail2), ..cs], s, next)
    }
    [#(t1, t2), ..] -> Error(error.TypeMismatch(t1, t2))
  }
}

// alg J with rows is interesting
// I think fsharp impl has bug of not accepting open rows at first pass

fn rewrite_row(new_label, row, s, next) { 
  case row {
    t.Empty -> Error(error.RowMismatch(new_label)) 
    t.RowExtend(label, value, tail) if label == new_label -> 
      Ok(#(value, tail, s, next))
    t.Var(a) -> {
      let #(value, next) = t.fresh(next)
      let #(tail, next) = t.fresh(next)
      let s = map.insert(s, a, t.RowExtend(new_label, value, tail))
      Ok(#(value, tail, s, next))
    }
    t.RowExtend(label, value, tail) -> {
      use #(value_new, tail_new, s, next) <- result.then(rewrite_row(new_label, tail, s, next))
      Ok(#(value_new, t.RowExtend(label, value, tail_new), s, next))
    }
    _ -> Error(error.InvalidTail(row))
  }
}

fn rewrite_effect(new_label, effect, s, next) { 
  case effect {
    t.Empty -> Error(error.RowMismatch(new_label)) 
    t.EffectExtend(label, #(lift, reply), tail) if label == new_label -> 
      Ok(#(lift, reply, tail, s, next))
    t.Var(a) -> {
      let #(lift, next) = t.fresh(next)
      let #(reply, next) = t.fresh(next)
      let #(tail, next) = t.fresh(next)
      let s = map.insert(s, a, t.EffectExtend(new_label, #(lift, reply), tail))
      Ok(#(lift, reply, tail, s, next))
    }
    t.EffectExtend(label, field, tail) -> {
      use #(lift_new, reply_new, tail_new, s, next) <- result.then(rewrite_effect(new_label, tail, s, next))
      Ok(#(lift_new, reply_new, t.EffectExtend(label, field, tail_new), s, next))
    }
    _ -> Error(error.InvalidTail(effect))
  }
}