import gleam/io
import gleam/list
import gleam/map.{Map}
import gleam/mapx
import gleam/result
import gleam/option.{None, Some}
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/analysis/substitutions as sub
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/env
import eyg/analysis/unification.{fresh, generalise, instantiate}
import gleam/javascript

// alg w
// alg w_fix
// alg w_equi
// alg w_iso

pub type Infered {
  // result could be separate map of errors
  Infered(
    substitutions: sub.Substitutions,
    types: Map(List(Int), Result(t.Term, unification.Failure)),
    environments: Map(List(Int), Map(String, Scheme)),
  )
}

pub fn type_of(inf: Infered, path) {
  let r = case map.get(inf.types, path) {
    Ok(r) -> r
    Error(Nil) -> {
      io.debug(path)
      // todo("invalid path")
      Error(unification.MissingVariable("bad path"))
    }
  }
  case r {
    Ok(t) -> Ok(unification.resolve(inf.substitutions, t))
    Error(reason) -> Error(reason)
  }
}

pub fn sound(inferred: Infered) {
  let errors = map.filter(inferred.types, fn(k, v) { result.is_error(v) })
  case map.size(errors) == 0 {
    True -> Ok(Nil)
    False -> Error(errors)
  }
}

fn apply(inf: Infered, typ) {
  sub.apply(inf.substitutions, typ)
}

fn apply_row(inf: Infered, row) {
  sub.apply_row(inf.substitutions, row)
}

fn apply_effects(inf: Infered, eff) {
  sub.apply_effects(inf.substitutions, eff)
}

fn env_apply(inf: Infered, env) {
  env.apply(inf.substitutions, env)
}

fn compose(inf1: Infered, inf2: Infered) {
  Infered(
    sub.compose(inf1.substitutions, inf2.substitutions),
    map.merge(inf1.types, inf2.types),
    map.merge(inf1.environments, inf2.environments),
  )
}

fn unify(t1, t2, ref, path) {
  case unification.unify(t1, t2, ref) {
    Ok(s) -> Infered(s, mapx.singleton(list.reverse(path), Ok(t1)), map.new())
    Error(reason) ->
      Infered(
        sub.none(),
        mapx.singleton(list.reverse(path), Error(reason)),
        map.new(),
      )
  }
}

fn unify_row(r1, r2, ref, path) {
  case unification.unify_row(r1, r2, ref) {
    Ok(s) -> Infered(s, map.new(), map.new())
    Error(reason) ->
      Infered(
        sub.none(),
        mapx.singleton(list.reverse(path), Error(reason)),
        map.new(),
      )
  }
}

fn unify_effects(e1, e2, ref, path) {
  case unification.unify_effects(e1, e2, ref) {
    Ok(s) -> Infered(s, map.new(), map.new())
    Error(reason) ->
      Infered(
        sub.none(),
        mapx.singleton(list.reverse(path), Error(reason)),
        map.new(),
      )
  }
}

// CPS style infer can be resumed so same infer and infer with path fn
// There is an always feed state through version using `use` that doesn't compose state but add's to single version
// don't make too pretty here

pub fn infer(env, exp, typ, eff) {
  do_infer(env, exp, typ, eff, javascript.make_reference(0), [])
}

fn do_infer(env, exp, typ, eff, ref, path) {
  case exp {
    e.Lambda(arg, body) -> {
      let t = t.Unbound(fresh(ref))
      let u = t.Unbound(fresh(ref))
      let r = t.Open(fresh(ref))
      let s1 = unify(typ, t.Fun(t, r, u), ref, path)
      let env =
        env_apply(s1, env)
        |> map.insert(arg, Scheme([], apply(s1, t)))
      let s2 =
        do_infer(
          env,
          body,
          apply(s1, u),
          apply_effects(s1, r),
          ref,
          [0, ..path],
        )
      compose(s2, s1)
    }
    e.Apply(func, arg) -> {
      let t = t.Unbound(fresh(ref))
      // TODO fix this so that dont need self unify to add path to sub
      // just point path to typ at top of do_infer but need to check map for errors separatly
      let s0 = unify(typ, typ, ref, path)
      let s1 = do_infer(env, func, t.Fun(t, eff, typ), eff, ref, [0, ..path])
      let s1 = compose(s1, s0)
      let s2 =
        do_infer(
          env_apply(s1, env),
          arg,
          apply(s1, t),
          apply_effects(s1, eff),
          ref,
          [1, ..path],
        )
      compose(s2, s1)
    }
    e.Variable(x) ->
      case map.get(env, x) {
        Ok(scheme) -> {
          let t = instantiate(scheme, ref)
          unify(typ, t, ref, path)
        }
        Error(Nil) ->
          Infered(
            sub.none(),
            mapx.singleton(
              list.reverse(path),
              Error(unification.MissingVariable(x)),
            ),
            map.new(),
          )
      }
    e.Let(x, value, then) -> {
      let t = t.Unbound(fresh(ref))
      let s1 = do_infer(env, value, t, eff, ref, [0, ..path])
      let scheme = generalise(env_apply(s1, env), apply(s1, t))
      let env = env_apply(s1, map.insert(env, x, scheme))
      let s2 =
        do_infer(
          env,
          then,
          apply(s1, typ),
          apply_effects(s1, eff),
          ref,
          [1, ..path],
        )
      compose(s2, s1)
      // TODO remove but needed for path to typ to exist in state
      |> compose(unify(typ, typ, ref, path))
    }
    // Primitive
    e.Binary(_) -> unify(typ, t.Binary, ref, path)
    e.Integer(_) -> unify(typ, t.Integer, ref, path)
    e.Tail -> unify(typ, t.LinkedList(t.Unbound(fresh(ref))), ref, path)
    e.Cons -> {
      let t = t.Unbound(fresh(ref))
      let e1 = t.Open(fresh(ref))
      let e2 = t.Open(fresh(ref))
      t.Fun(t, e1, t.Fun(t.LinkedList(t), e2, t.LinkedList(t)))
      |> unify(typ, _, ref, path)
    }

    e.Vacant ->
      Infered(
        sub.none(),
        mapx.singleton(list.reverse(path), Ok(typ)),
        map.new(),
      )

    e.Record(fields, tail) -> {
      let row = t.Open(fresh(ref))
      // if type already defined then this unifies the fields inference
      let s1 = unify(typ, t.Record(row), ref, path)
      let row = apply_row(s1, row)
      let #(unchanged, s2, update, _) =
        list.fold_right(
          fields,
          #(row, s1, [], 1),
          fn(state, field) {
            let #(label, value) = field
            let #(r, s1, update, index) = state
            let t = t.Unbound(fresh(ref))
            let next = t.Open(fresh(ref))
            let s2 = unify_row(r, t.Extend(label, t, next), ref, path)
            let s3 = compose(s2, s1)
            let t = apply(s3, t)
            let eff = apply_effects(s3, eff)
            let s4 = do_infer(env, value, t, eff, ref, [index, ..path])
            let s5 = compose(s4, s3)
            #(apply_row(s5, next), s5, [label, ..update], index + 1)
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
              let s4 = unify(t.Record(row), previous, ref, [0, ..path])
              compose(s4, s3)
            }
            Error(_) -> todo("missing tail")
          }
        None -> {
          // If there is no variable we are creating a record and therefor it has no tail
          let s4 = unify_row(unchanged, t.Closed, ref, path)
          compose(s4, s3)
        }
      }
    }
    e.Empty -> {
      let t = t.Record(t.Closed)
      unify(typ, t, ref, path)
    }
    e.Extend(label) -> {
      let t = t.Unbound(fresh(ref))
      let r = t.Open(fresh(ref))
      let e1 = t.Open(fresh(ref))
      let e2 = t.Open(fresh(ref))
      t.Fun(t, e1, t.Fun(t.Record(r), e2, t.Record(t.Extend(label, t, r))))
      |> unify(typ, _, ref, path)
    }
    e.Overwrite(label) -> {
      let t = t.Unbound(fresh(ref))
      let u = t.Unbound(fresh(ref))
      let r = t.Open(fresh(ref))
      let e1 = t.Open(fresh(ref))
      let e2 = t.Open(fresh(ref))
      t.Fun(
        t,
        e1,
        t.Fun(
          t.Record(t.Extend(label, u, r)),
          e2,
          t.Record(t.Extend(label, t, r)),
        ),
      )
      |> unify(typ, _, ref, path)
    }
    e.Select(label) -> {
      let t = t.Unbound(fresh(ref))
      let r = t.Open(fresh(ref))
      let e = t.Open(fresh(ref))
      unify(typ, t.Fun(t.Record(t.Extend(label, t, r)), e, t), ref, path)
    }
    // Union
    e.Tag(label) -> {
      let t = t.Unbound(fresh(ref))
      let r = t.Open(fresh(ref))
      let e = t.Open(fresh(ref))
      unify(typ, t.Fun(t, e, t.Union(t.Extend(label, t, r))), ref, path)
    }
    e.Case(label) -> {
      let t = t.Unbound(fresh(ref))
      let ret = t.Unbound(fresh(ref))
      let r = t.Open(fresh(ref))
      let e1 = t.Open(fresh(ref))
      let e2 = t.Open(fresh(ref))
      let e3 = t.Open(fresh(ref))
      let e4 = t.Open(fresh(ref))
      let e5 = t.Open(fresh(ref))
      let branch = t.Fun(t, e1, ret)
      let else = t.Fun(t.Union(r), e2, ret)
      let exec = t.Fun(t.Union(t.Extend(label, t, r)), e3, ret)
      t.Fun(branch, e4, t.Fun(else, e5, exec))
      |> unify(typ, _, ref, path)
    }
    e.NoCases -> {
      // unbound return to match cases
      let t = t.Unbound(fresh(ref))
      let e = t.Open(fresh(ref))
      t.Fun(t.Union(t.Closed), e, t)
      |> unify(typ, _, ref, path)
    }
    e.Match(branches, tail) -> {
      let inner = t.Open(fresh(ref))
      let row = t.Open(fresh(ref))
      let ret = t.Unbound(fresh(ref))
      let needed = t.Fun(t.Union(row), inner, ret)
      let s1 = unify(typ, needed, ref, path)
      let #(s2, remaining, _index) =
        list.fold(
          branches,
          #(s1, apply_row(s1, row), 1),
          fn(state, branch) {
            let #(s1, row, index) = state
            let #(label, param, then) = branch
            let field_type = t.Unbound(fresh(ref))
            let remaining = t.Open(fresh(ref))
            let s2 =
              unify_row(row, t.Extend(label, field_type, remaining), ref, path)
            let s3 = compose(s2, s1)
            let env = map.insert(env, param, Scheme([], apply(s3, field_type)))
            let s4 =
              do_infer(
                env,
                then,
                apply(s3, ret),
                apply_effects(s3, inner),
                ref,
                [index, ..path],
              )
            let s5 = compose(s4, s3)
            #(s5, apply_row(s5, remaining), index + 1)
          },
        )
      // s2 already unifed with s1
      case tail {
        Some(#(param, then)) -> {
          let env = map.insert(env, param, Scheme([], t.Union(remaining)))
          let s3 =
            do_infer(
              env,
              then,
              apply(s2, ret),
              apply_effects(s2, inner),
              ref,
              // TODO move this to error branch
              // maybe zero not the best here
              [0, ..path],
            )
          compose(s3, s2)
        }
        None -> {
          let s3 = unify_row(remaining, t.Closed, ref, path)
          compose(s3, s2)
        }
      }
    }
    e.Perform(label) -> {
      let arg = t.Unbound(fresh(ref))
      let ret = t.Unbound(fresh(ref))
      let tail = t.Open(fresh(ref))
      unify(typ, t.Fun(arg, t.Extend(label, #(arg, ret), tail), ret), ref, path)
    }
    // handle
    e.Deep(var, branches) -> {
      // The effects for apply the fn must be open but not necessarily tied to eff in this context, they can be passed around
      // unit -> body is a defered computation
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
          t.Fun(t.Fun(t.unit, effects, ret), uncaught, ret),
        )
      let s1 = unify(typ, needed, ref, path)
      let #(s2, _extended, _) =
        list.fold(
          branches,
          #(s1, apply_effects(s1, uncaught), 0),
          fn(acc, branch) {
            let #(s1, row, index) = acc
            let #(label, param, kont, then) = branch
            let call = t.Unbound(fresh(ref))
            let reply = t.Unbound(fresh(ref))
            // What should this unify with
            let extended = t.Extend(label, #(call, reply), row)
            let s2 = unify_effects(effects, extended, ref, path)
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
              do_infer(
                env,
                then,
                apply(s3, ret),
                apply_effects(s3, eff),
                ref,
                [index, ..path],
              )
            let s5 = compose(s4, s3)
            let row = apply_effects(s5, extended)
            #(s5, row, index + 1)
          },
        )
      s2
    }
    e.Handle(_) -> todo("infer handle")
  }
  |> compose(Infered(
    sub.none(),
    map.new(),
    mapx.singleton(list.reverse(path), env),
  ))
}
