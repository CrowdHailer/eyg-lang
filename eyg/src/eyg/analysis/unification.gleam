import gleam/io
import gleam/list
import gleam/map.{Map}
import gleam/set
import gleam/result
import gleam/setx
import eyg/analysis/typ as t
// TODO manage without JS
import gleam/javascript

// TYPE
fn ftv(typ) {
  case typ {
    // TODO union type variables
    t.Fun(from, effects, to) -> set.union(ftv(from), ftv(to))
    t.Var(x) -> setx.singleton(TermVar(x))
    t.Integer | t.Binary -> set.new()
    // t.Record(row) -> ftv_row(row)
    // t.Union(row) -> ftv_row(row)
    _ -> todo("ftv")
  }
}

// Top level
// fn ftv_row(row) {
//   case row {
//     RowClosed -> set.new()
//     RowOpen(x) -> setx.singleton(RowVar(x))
//     RowExtend(_label, value, tail) -> set.union(ftv(value), ftv_row(tail))
//   }
// }

pub type KindVar {
  TermVar(Int)
  RowVar(Int)
}

// Normal
pub fn fresh(ref) {
  javascript.update_reference(ref, fn(x) { x + 1 })
}

pub type Substitutions {
  // TODO this needs annother effects lookup
  Substitutions(
    terms: Map(Int, t.Type),
    rows: Map(Int, t.Row(t.Type)),
    effs: Map(Int, t.Row(#(t.Type, t.Type))),
  )
}

fn sub_empty() {
  Substitutions(map.new(), map.new(), map.new())
}

fn set_drop(set, nope) {
  list.fold(nope, set, set.delete)
}

// TODO move to scheme
pub type Scheme {
  Scheme(forall: List(KindVar), type_: t.Type)
}

fn ftv_scheme(scheme) {
  let Scheme(forall, typ) = scheme
  set_drop(ftv(typ), forall)
}

fn drop(sub: Substitutions, vars) {
  list.fold(
    vars,
    sub,
    fn(sub, var) {
      let Substitutions(terms, rows, effs) = sub
      case var {
        TermVar(x) -> Substitutions(map.drop(terms, [x]), rows, effs)
        RowVar(x) -> Substitutions(terms, map.drop(rows, [x]), effs)
      }
    },
  )
}

fn apply_scheme(sub, scheme) {
  let Scheme(forall, typ) = scheme
  Scheme(forall, apply(drop(sub, forall), typ))
}

type TypeEnv =
  Map(String, Scheme)

// TypeEnv
fn ftv_env(env: TypeEnv) {
  map.fold(
    env,
    set.new(),
    fn(state, _k, scheme) { set.union(state, ftv_scheme(scheme)) },
  )
}

pub fn apply_env(sub, env) {
  map.map_values(env, fn(_k, scheme) { apply_scheme(sub, scheme) })
}

pub fn apply(sub: Substitutions, typ) {
  case typ {
    t.Var(x) ->
      case map.get(sub.terms, x) {
        Ok(replace) -> replace
        Error(Nil) -> typ
      }
    t.Fun(from, effects, to) ->
      t.Fun(apply(sub, from), apply_effects(sub, effects), apply(sub, to))
    // TRecord(row) -> TRecord(apply_row(sub, row, apply))
    // TUnion(row) -> TUnion(apply_row(sub, row, apply))
    t.Integer | t.Binary -> typ
    _ -> todo("apply")
  }
}

pub fn apply_row(sub: Substitutions, row) {
  case row {
    t.RowClosed -> t.RowClosed
    t.RowOpen(x) ->
      case map.get(sub.rows, x) {
        Ok(replace) -> replace
        Error(Nil) -> row
      }
    t.RowExtend(label, value, tail) ->
      t.RowExtend(label, apply(sub, value), apply_row(sub, tail))
  }
}

pub fn apply_effects(sub: Substitutions, effect) {
  case effect {
    t.RowClosed -> t.RowClosed
    t.RowOpen(x) ->
      case map.get(sub.effs, x) {
        Ok(replace) -> replace
        Error(Nil) -> effect
      }
    t.RowExtend(label, #(in, out), tail) ->
      t.RowExtend(
        label,
        #(apply(sub, in), apply(sub, out)),
        apply_effects(sub, tail),
      )
  }
  // RowExtend(label, apply(sub, value), apply_row(sub, tail, apply))
}

pub fn compose(sub1: Substitutions, sub2: Substitutions) {
  let terms =
    map.merge(
      map.map_values(sub2.terms, fn(_k, v) { apply(sub1, v) }),
      sub1.terms,
    )
  let rows =
    map.merge(
      map.map_values(sub2.rows, fn(_k, v) { apply_row(sub1, v) }),
      sub1.rows,
    )
  // TODO
  let effs = sub1.effs

  // map.merge(
  //   map.map_values(sub2.rows, fn(_k, v) { apply_row(sub1, v, apply) }),
  //   sub1.rows,
  // )
  Substitutions(terms, rows, effs)
}

pub fn generalise(env: Map(String, Scheme), typ) {
  let variables = set.to_list(set_drop(ftv_env(env), set.to_list(ftv(typ))))
  Scheme(variables, typ)
}

pub fn instantiate(scheme, ref) {
  let Scheme(vars, typ) = scheme
  let s =
    list.fold(
      vars,
      //   TODO empty fn
      Substitutions(map.new(), map.new(), map.new()),
      fn(sub, v) {
        let Substitutions(terms, rows, effs) = sub
        case v {
          TermVar(x) ->
            Substitutions(map.insert(terms, x, t.Var(fresh(ref))), rows, effs)
          RowVar(x) ->
            Substitutions(
              terms,
              map.insert(rows, x, t.RowOpen(fresh(ref))),
              effs,
            )
        }
      },
    )

  apply(s, typ)
}

fn varbind(u, typ) {
  case typ {
    t.Var(x) if x == u -> sub_empty()
    _ ->
      case set.contains(ftv(typ), TermVar(u)) {
        True -> {
          map.new()
          todo("RECURSION IS BACK")
        }
        False -> {
          let terms =
            map.new()
            |> map.insert(u, typ)
          Substitutions(terms, map.new(), map.new())
        }
      }
  }
}

pub fn unify(t1, t2) {
  case t1, t2 {
    t.Fun(from1, effects1, to1), t.Fun(from2, effects2, to2) -> {
      let s1 = unify(from1, from2)
      let s2 = unify(apply(s1, to1), apply(s1, to2))
      // io.debug(effects1)
      // io.debug(effects2)
      let s3 = compose(s2, s1)
      // apply row pulls out of substitutions
      // apply_effects(s3, effects1, fn(s, r) { Nil })
      unify_effects(apply_effects(s3, effects1), apply_effects(s3, effects2))
    }
    t.Var(u), t | t, t.Var(u) -> varbind(u, t)
    t.Binary, t.Binary -> sub_empty()
    t.Integer, t.Integer -> sub_empty()
    _, _ -> {
      io.debug(#(t1, t2))
      todo("unify")
    }
  }
}

fn unify_effects(eff1, eff2) {
  case eff1, eff2 {
    t.RowClosed, t.RowClosed -> Substitutions(map.new(), map.new(), map.new())
    t.RowOpen(u), t.RowOpen(v) if u == v ->
      Substitutions(map.new(), map.new(), map.new())
    t.RowOpen(u), r | r, t.RowOpen(u) -> {
      let effs =
        map.new()
        |> map.insert(u, r)
      Substitutions(map.new(), map.new(), effs)
    }
  }
}

pub fn resolve(sub, typ) {
  let Substitutions(terms: terms, ..) = sub
  case typ {
    t.Var(a) ->
      map.get(terms, a)
      |> result.unwrap(typ)
    t.Binary | t.Integer -> typ
    _ -> todo("resolve")
  }
}
