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
import eyg/analysis/unification.{
  fresh, generalise, instantiate, unify, unify_effects, unify_row,
}

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
      let s2 = infer(env, body, apply(s1, u), apply_effects(s1, r), ref)
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
        Error(Nil) -> {
          io.debug(x)
          todo("inconsis variable")
        }
      }
    e.Let(x, value, then) -> {
      let t = t.Unbound(fresh(ref))
      let s1 = infer(env, value, t, eff, ref)
      let scheme = generalise(env.apply(s1, env), apply(s1, t))
      let env = env.apply(s1, map.insert(env, x, scheme))
      let s2 = infer(env, then, apply(s1, typ), apply_effects(s1, eff), ref)
      compose(s2, s1)
    }
    // Primitive
    e.Binary -> unify(typ, t.Binary, ref)
    e.Integer -> unify(typ, t.Integer, ref)
    e.Vacant -> sub.none()

    e.Record(fields, tail) -> {
      let row = t.Open(fresh(ref))
      // if type already defined then this unifies the fields inference
      let s1 = unify(typ, t.Record(row), ref)
      let row = apply_row(s1, row)
      let #(unchanged, s2, update) =
        list.fold_right(
          fields,
          #(row, s1, []),
          fn(state, field) {
            let #(label, value) = field
            let #(r, s1, update) = state
            let t = t.Unbound(fresh(ref))
            let next = t.Open(fresh(ref))
            let s2 = unify_row(r, t.Extend(label, t, next), ref)
            let s3 = compose(s2, s1)
            let t = apply(s3, t)
            let eff = apply_effects(s3, eff)
            let s4 = infer(env, value, t, eff, ref)
            let s5 = compose(s4, s3)
            #(apply_row(s5, next), s5, [label, ..update])
          },
        )
      let s3 = compose(s2, s1)
      case tail {
        Some(var) ->
          case map.get(env, var) {
            Ok(scheme) -> {
              let previous = instantiate(scheme, ref)
              // If there is a variable we assume update semantics, not extend.
              // A new type var is instantiated for each field because we allow type changes.
              // For extend we could unify without applying the update fields.
              let row =
                list.fold(
                  update,
                  apply_row(s3, unchanged),
                  fn(row, label) { t.Extend(label, t.Unbound(fresh(ref)), row) },
                )
              let s4 = unify(t.Record(row), previous, ref)
              compose(s4, s3)
            }
            Error(_) -> todo("missing tail")
          }
        None -> {
          // If there is no variable we are creating a record and therefor it has no tail
          let s4 = unify_row(unchanged, t.Closed, ref)
          compose(s4, s3)
        }
      }
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
    // TODO this becomes apply
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
    // handle
    e.Deep(var, branches) -> {
      // The effects for apply the fn must be open but not necessarily tied to eff in this context, they can be passed around
      // TODO move unit && thunk to t
      // unit -> body is a defered computation
      let unit = t.Record(t.Closed)
      // linking parts of the handler, ret is same before and after handler applies, see examples
      let state = t.Unbound(fresh(ref))
      let ret = t.Unbound(fresh(ref))
      // effects consist of all in this handler and all uncaught
      let uncaught = t.Open(fresh(ref))
      let effects = t.Open(fresh(ref))
      let needed =
        t.Fun(
          state,
          t.Open(fresh(ref)),
          t.Fun(t.Fun(unit, effects, ret), uncaught, ret),
        )
      let s1 = unify(typ, needed, ref)
      let #(s2, extended) =
        list.fold(
          branches,
          #(s1, apply_effects(s1, uncaught)),
          fn(acc, branch) {
            let #(s1, row) = acc
            let #(label, param, kont, then) = branch
            let call = t.Unbound(fresh(ref))
            let reply = t.Unbound(fresh(ref))
            // What should this unify with
            let extended = t.Extend(label, #(call, reply), row)
            let s2 = unify_effects(effects, extended, ref)
            let s3 = compose(s2, s1)
            let env =
              env
              |> map.insert(var, Scheme([], state))
              |> map.insert(param, Scheme([], apply(s3, call)))
              |> map.insert(
                kont,
                Scheme(
                  [],
                  t.Fun(
                    state,
                    t.Open(fresh(ref)),
                    t.Fun(reply, effects, apply(s3, ret)),
                  ),
                ),
              )
            let s4 =
              infer(env, then, apply(s3, ret), apply_effects(s3, eff), ref)
            let s5 = compose(s4, s3)
            let row = apply_effects(s5, extended)
            #(s5, row)
          },
        )
      s2
    }
  }
}
