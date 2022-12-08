import gleam/io
import gleam/list
import gleam/map
import gleam/option.{None, Some}
import eyg/analysis/expression as e
import eyg/analysis/typ as t
import eyg/analysis/substitutions.{apply,
  apply_effects, apply_row, compose} as sub
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/env
import eyg/analysis/unification.{fresh, generalise, instantiate, unify}

// alg w
// alg w_fix
// alg w_equi
// alg w_iso

pub fn infer(env, exp, typ, eff, ref) {
  case exp {
    e.Lambda(arg, body) -> {
      let t = t.Unbound(fresh(ref))
      let u = t.Unbound(fresh(ref))
      let r = t.Open(fresh(ref))
      let s1 = unify(typ, t.Fun(t, r, u), ref)
      let env =
        env.apply(s1, env)
        |> map.insert(arg, Scheme([], apply(s1, t)))
      let s2 = infer(env, body, apply(s1, u), r, ref)
      compose(s2, s1)
    }
    e.Apply(func, arg) -> {
      let t = t.Unbound(fresh(ref))
      let s1 = infer(env, func, t.Fun(t, eff, typ), eff, ref)
      let s2 =
        infer(
          env.apply(s1, env),
          arg,
          apply(s1, t),
          apply_effects(s1, eff),
          ref,
        )
      compose(s2, s1)
    }
    e.Variable(x) ->
      case map.get(env, x) {
        Ok(scheme) -> {
          let t = instantiate(scheme, ref)
          unify(typ, t, ref)
        }
        Error(Nil) -> todo("inconsis variable")
      }
    e.Let(x, value, then) -> {
      let t = t.Unbound(fresh(ref))
      let s1 = infer(env, value, t, eff, ref)
      let scheme = generalise(env.apply(s1, env), apply(s1, t))
      let env = env.apply(s1, map.insert(env, x, scheme))
      let s2 = infer(env, then, typ, eff, ref)
      compose(s2, s1)
    }
    // Primitive
    e.Binary -> unify(typ, t.Binary, ref)
    e.Integer -> unify(typ, t.Integer, ref)
    e.Vacant -> sub.none()

    // Record creation
    e.Record(fields, None) -> {
      let #(s1, row) =
        list.fold(fields, #(sub.none(), t.Closed), infer_record(env, eff, ref))
      let s2 = unify(typ, t.Record(row), ref)
      compose(s2, s1)
    }

    // Record update
    e.Record(fields, Some(x)) ->
      case map.get(env, x) {
        Ok(scheme) -> {
          let root = instantiate(scheme, ref)
          let s0 = unify(typ, root, ref)
          let #(s1, row) =
            list.fold(
              fields,
              #(s0, t.Open(fresh(ref))),
              infer_record(env, eff, ref),
            )
          let s2 = compose(s1, s0)
          let s3 = unify(apply(s2, typ), apply(s2, t.Record(row)), ref)
          compose(s3, s2)
        }
        Error(Nil) -> todo("missing record to extend variable")
      }
    e.Select(label) -> {
      let t = t.Unbound(fresh(ref))
      let r = t.Open(fresh(ref))
      let e = t.Open(fresh(ref))
      unify(typ, t.Fun(t.Record(t.Extend(label, t, r)), e, t), ref)
    }
    // Union
    e.Tag(label) -> {
      let t = t.Unbound(fresh(ref))
      let r = t.Open(fresh(ref))
      let e = t.Open(fresh(ref))
      unify(typ, t.Fun(t, e, t.Union(t.Extend(label, t, r))), ref)
    }
    e.Match(value, branches, tail) -> {
      let state = case tail {
        Some(#(param, then)) -> {
          let tail = t.Open(fresh(ref))
          let env = map.insert(env, param, Scheme([], t.Union(tail)))
          let s = infer(env, then, typ, eff, ref)
          #(s, sub.apply_row(s, tail))
        }
        None -> #(sub.none(), t.Closed)
      }
      let #(s1, row) =
        list.fold(
          branches,
          state,
          fn(state, branch) {
            let #(s1, row) = state
            let #(label, param, then) = branch
            let field_type = t.Unbound(fresh(ref))
            let env = map.insert(env, param, Scheme([], field_type))
            let s2 =
              infer(
                env,
                then,
                sub.apply(s1, typ),
                sub.apply_effects(s1, eff),
                ref,
              )
            let s3 = compose(s2, s1)
            let row =
              t.Extend(label, sub.apply(s3, field_type), sub.apply_row(s3, row))
            #(s3, row)
          },
        )
      let s2 = infer(env, value, t.Union(row), eff, ref)
      compose(s2, s1)
    }
    e.Perform(label) -> {
      let arg = t.Unbound(fresh(ref))
      let ret = t.Unbound(fresh(ref))
      let tail = t.Open(fresh(ref))
      unify(typ, t.Fun(arg, t.Extend(label, #(arg, ret), tail), ret), ref)
    }
  }
}

fn infer_record(env, eff, ref) {
  fn(state, field) {
    let #(s1, row) = state
    let #(label, value) = field
    let t = t.Unbound(fresh(ref))
    let s2 =
      infer(env, value, sub.apply(s1, t), sub.apply_effects(s1, eff), ref)
    let s3 = compose(s2, s1)
    #(s3, t.Extend(label, sub.apply(s3, t), sub.apply_row(s3, row)))
  }
}
