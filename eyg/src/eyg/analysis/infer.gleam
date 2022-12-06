import gleam/io
import gleam/map
import eyg/analysis/expression as e
import eyg/analysis/typ as t
// same
import eyg/analysis/unification.{
  apply, apply_effects, apply_env, apply_row, compose, fresh, generalise,
  instantiate, unify,
}

pub fn empty_env() {
  map.new()
}

pub fn infer(env, exp, typ, eff, ref) {
  case exp {
    e.Lambda(arg, body) -> {
      let t = t.Var(fresh(ref))
      let u = t.Var(fresh(ref))
      let r = t.RowOpen(fresh(ref))
      let s1 = unify(typ, t.Fun(t, r, u))
      let env =
        apply_env(s1, env)
        |> map.insert(arg, unification.Scheme([], apply(s1, t)))
      let s2 = infer(env, body, apply(s1, u), r, ref)
      compose(s2, s1)
    }
    e.Apply(func, arg) -> {
      let t = t.Var(fresh(ref))
      io.debug(#("soooo", typ, t))
      let s1 = infer(env, func, t.Fun(t, eff, typ), eff, ref)
      io.debug(t)
      io.debug(s1)
      let s2 =
        infer(
          apply_env(s1, env),
          arg,
          apply(s1, t),
          apply_effects(s1, eff),
          ref,
        )
      io.debug(s2)
      compose(s2, s1)
    }
    e.Variable(x) ->
      case map.get(env, x) {
        Ok(scheme) -> {
          let t = instantiate(scheme, ref)
          io.debug(#(t, "=============env"))
          unify(typ, t)
        }
        Error(Nil) -> todo("inconsis variable")
      }
    e.Let(x, value, then) -> {
      let t = t.Var(fresh(ref))
      let s1 = infer(env, value, t, eff, ref)
      let scheme = generalise(apply_env(s1, env), apply(s1, t))
      //   TODO substitution application on env
      let env = map.insert(env, x, scheme)
      infer(env, then, typ, eff, ref)
    }
    // Primitive
    e.Binary -> unify(typ, t.Binary)
    e.Integer -> unify(typ, t.Integer)
    _ -> todo("inference")
  }
}
