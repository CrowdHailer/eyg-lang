import gleam/list
import gleam/map
import gleam/set
import gleam/result
import eyg/analysis/typ as t
import eyg/analysis/substitutions as sub
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/env
import gleam/javascript

// Normal
pub fn fresh(ref) {
  javascript.update_reference(ref, fn(x) { x + 1 })
}

pub fn generalise(env, typ) {
  let variables = set.to_list(set.drop(t.ftv(typ), set.to_list(env.ftv(env))))
  Scheme(variables, typ)
}

pub fn instantiate(scheme, ref) {
  let Scheme(vars, typ) = scheme

  let insert_fresh = fn(s, v) {
    case v {
      t.Term(x) -> sub.insert_term(s, x, t.Unbound(fresh(ref)))
      t.Row(x) -> sub.insert_row(s, x, t.Open(fresh(ref)))
      t.Effect(x) -> sub.insert_effect(s, x, t.Open(fresh(ref)))
    }
  }

  list.fold(vars, sub.none(), insert_fresh)
  |> sub.apply(typ)
}

fn varbind(u, typ) {
  case typ {
    t.Unbound(x) if x == u -> Ok(sub.none())
    _ ->
      case set.contains(t.ftv(typ), t.Term(u)) {
        True -> Error(RecursiveType)
        False -> Ok(sub.term(u, typ))
      }
  }
}

pub type Failure {
  TypeMismatch(t.Term, t.Term)
  RowMismatch(String)
  MissingVariable(String)
  RecursiveType
}

pub fn unify(t1, t2, ref) -> Result(_, _) {
  case t1, t2 {
    t.Fun(from1, effects1, to1), t.Fun(from2, effects2, to2) -> {
      use s1 <- result.then(unify(from1, from2, ref))
      use s2 <- result.then(unify(sub.apply(s1, to1), sub.apply(s1, to2), ref))
      let s3 = sub.compose(s2, s1)
      use s4 <- result.then(unify_effects(
        sub.apply_effects(s3, effects1),
        sub.apply_effects(s3, effects2),
        ref,
      ))
      Ok(sub.compose(s4, s3))
    }
    t.Unbound(u), t | t, t.Unbound(u) -> varbind(u, t)
    t.Str, t.Str -> Ok(sub.none())
    t.Integer, t.Integer -> Ok(sub.none())
    t.LinkedList(i1), t.LinkedList(i2) -> unify(i1, i2, ref)
    t.Record(r1), t.Record(r2) -> unify_row(r1, r2, ref)
    t.Union(r1), t.Union(r2) -> unify_row(r1, r2, ref)
    _, _ -> Error(TypeMismatch(t1, t2))
  }
}

fn rewrite_row(row, new_label, ref) {
  case row {
    t.Closed -> Error(RowMismatch(new_label))
    t.Extend(label, field, tail) if label == new_label ->
      Ok(#(field, tail, sub.none()))
    t.Open(old) -> {
      let t = t.Unbound(fresh(ref))
      let r = t.Open(fresh(ref))
      let s = sub.row(old, t.Extend(new_label, t, r))
      Ok(#(t, r, s))
    }
    t.Extend(label, field, tail) -> {
      use #(field1, tail1, subs) <- result.then(rewrite_row(
        tail,
        new_label,
        ref,
      ))
      Ok(#(field1, t.Extend(label, field, tail1), subs))
    }
  }
}

pub fn unify_row(r1, r2, ref) {
  case r1, r2 {
    t.Closed, t.Closed -> Ok(sub.none())
    t.Open(u), t.Open(v) if u == v -> Ok(sub.none())
    t.Open(u), r | r, t.Open(u) -> Ok(sub.row(u, r))
    // I think all possible cominations the reach this point in the case are extend constructors from this point
    t.Extend(label, t1, tail1), r | r, t.Extend(label, t1, tail1) -> {
      use #(t2, tail2, s1) <- result.then(rewrite_row(r, label, ref))
      use s2 <- result.then(unify(sub.apply(s1, t1), sub.apply(s1, t2), ref))
      let s3 = sub.compose(s2, s1)
      use s4 <- result.then(unify_row(
        sub.apply_row(s3, tail1),
        sub.apply_row(s3, tail2),
        ref,
      ))
      Ok(sub.compose(s4, s3))
    }
  }
}

// looks like rewrite row but reference to sub.effect and creating fresh is specific
fn rewrite_effect(effect, new_label, ref) {
  case effect {
    t.Closed -> Error(RowMismatch(new_label))
    t.Extend(label, field, tail) if label == new_label ->
      Ok(#(field, tail, sub.none()))
    t.Open(old) -> {
      let t = #(t.Unbound(fresh(ref)), t.Unbound(fresh(ref)))
      let r = t.Open(fresh(ref))
      let s = sub.effect(old, t.Extend(new_label, t, r))
      Ok(#(t, r, s))
    }
    t.Extend(label, field, tail) -> {
      use #(field1, tail1, subs) <- result.then(rewrite_effect(
        tail,
        new_label,
        ref,
      ))
      Ok(#(field1, t.Extend(label, field, tail1), subs))
    }
  }
}

pub fn unify_effects(eff1, eff2, ref) {
  case eff1, eff2 {
    t.Closed, t.Closed -> Ok(sub.none())
    t.Open(u), t.Open(v) if u == v -> Ok(sub.none())
    t.Open(u), r | r, t.Open(u) -> Ok(sub.effect(u, r))
    // I think all possible cominations the reach this point in the case are extend constructors from this point
    t.Extend(label, #(t1, u1), tail1), r | r, t.Extend(label, #(t1, u1), tail1) -> {
      use #(#(t2, u2), tail2, s1) <- result.then(rewrite_effect(r, label, ref))
      use s2 <- result.then(unify(sub.apply(s1, t1), sub.apply(s1, t2), ref))
      let s3 = sub.compose(s2, s1)
      use s4 <- result.then(unify(sub.apply(s1, u1), sub.apply(s1, u2), ref))
      let s5 = sub.compose(s4, s3)
      use s6 <- result.then(unify_effects(
        sub.apply_effects(s5, tail1),
        sub.apply_effects(s5, tail2),
        ref,
      ))
      Ok(sub.compose(s6, s5))
    }
  }
}

pub fn resolve(s, typ) {
  let sub.Substitutions(terms: terms, ..) = s
  case typ {
    t.Unbound(a) ->
      map.get(terms, a)
      |> result.unwrap(typ)
    t.Binary | t.Str | t.Integer -> typ
    t.LinkedList(element) -> t.LinkedList(resolve(s, element))
    t.Fun(t, e, u) -> t.Fun(resolve(s, t), resolve_effect(s, e), resolve(s, u))
    t.Record(r) -> t.Record(resolve_row(s, r))
    t.Union(r) -> t.Union(resolve_row(s, r))
  }
}

pub fn resolve_row(sub: sub.Substitutions, row) {
  case row {
    t.Closed -> row
    t.Open(r) ->
      map.get(sub.rows, r)
      |> result.unwrap(row)
    t.Extend(label, value, tail) ->
      t.Extend(label, resolve(sub, value), resolve_row(sub, tail))
  }
}

pub fn resolve_effect(sub: sub.Substitutions, effects) {
  case effects {
    t.Closed -> effects
    t.Open(r) ->
      map.get(sub.effects, r)
      |> result.unwrap(effects)
    t.Extend(label, #(lift, reply), tail) -> {
      let effect = #(resolve(sub, lift), resolve(sub, reply))
      t.Extend(label, effect, resolve_effect(sub, tail))
    }
  }
}
