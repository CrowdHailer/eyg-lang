import gleam/map
import eyg/analysis/expression as e
import eyg/analysis/typ as t
// same
import eyg/analysis/unification.{
  apply, apply_env, fresh, generalise, instantiate, unify,
}

pub fn empty_env() {
  map.new()
}

pub fn infer(env, exp, typ, eff, ref) {
  case exp {
    e.Variable(x) ->
      case map.get(env, x) {
        Ok(scheme) -> {
          let t = instantiate(scheme, ref)
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
