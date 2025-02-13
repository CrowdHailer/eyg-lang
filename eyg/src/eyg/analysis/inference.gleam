import eyg/analysis/env
import eyg/analysis/scheme.{type Scheme, Scheme}
import eyg/analysis/substitutions as sub
import eyg/analysis/typ as t
import eyg/analysis/unification.{fresh, generalise, instantiate}
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/dictx
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import harness/stdlib
import javascript/mutable_reference as ref

pub type Infered {
  // result could be separate map of errors
  Infered(
    substitutions: sub.Substitutions,
    types: Dict(List(Int), Result(t.Term, unification.Failure)),
    environments: Dict(List(Int), Dict(String, Scheme)),
  )
}

pub fn type_of(inf: Infered, path) {
  let r = case dict.get(inf.types, path) {
    Ok(r) -> r
    Error(Nil) -> {
      io.debug(path)
      Error(unification.MissingVariable("bad path"))
    }
  }
  case r {
    Ok(t) -> Ok(unification.resolve(inf.substitutions, t))
    Error(reason) -> Error(reason)
  }
}

pub fn sound(inferred: Infered) {
  let errors = dict.filter(inferred.types, fn(_k, v) { result.is_error(v) })
  case dict.size(errors) == 0 {
    True -> Ok(Nil)
    False -> Error(errors)
  }
}

fn apply(inf: Infered, typ) {
  sub.apply(inf.substitutions, typ)
}

// fn apply_row(inf: Infered, row) {
//   sub.apply_row(inf.substitutions, row)
// }

fn apply_effects(inf: Infered, eff) {
  sub.apply_effects(inf.substitutions, eff)
}

fn env_apply(inf: Infered, env) {
  env.apply(inf.substitutions, env)
}

fn compose(inf1: Infered, inf2: Infered) {
  Infered(
    sub.compose(inf1.substitutions, inf2.substitutions),
    dict.merge(inf1.types, inf2.types),
    dict.merge(inf1.environments, inf2.environments),
  )
}

fn unify(t1, t2, ref, path) {
  case unification.unify(t1, t2, ref) {
    Ok(s) -> Infered(s, dictx.singleton(list.reverse(path), Ok(t1)), dict.new())
    Error(reason) ->
      Infered(
        sub.none(),
        dictx.singleton(list.reverse(path), Error(reason)),
        dict.new(),
      )
  }
}

// fn unify_row(r1, r2, ref, path) {
//   case unification.unify_row(r1, r2, ref) {
//     Ok(s) -> Infered(s, dict.new(), dict.new())
//     Error(reason) ->
//       Infered(
//         sub.none(),
//         dictx.singleton(list.reverse(path), Error(reason)),
//         dict.new(),
//       )
//   }
// }

// fn unify_effects(e1, e2, ref, path) {
//   case unification.unify_effects(e1, e2, ref) {
//     Ok(s) -> Infered(s, dict.new(), dict.new())
//     Error(reason) ->
//       Infered(
//         sub.none(),
//         dictx.singleton(list.reverse(path), Error(reason)),
//         dict.new(),
//       )
//   }
// }

// CPS style infer can be resumed so same infer and infer with path fn
// There is an always feed state through version using `use` that doesn't compose state but add's to single version
// don't make too pretty here

pub fn infer(env, exp, typ, eff) {
  do_infer(env, exp, typ, eff, ref.new(0), [])
}

fn do_infer(env, exp, typ, eff, ref, path) {
  let #(exp, _) = exp
  case exp {
    ir.Lambda(arg, body) -> {
      let t = t.Unbound(fresh(ref))
      let u = t.Unbound(fresh(ref))
      let r = t.Open(fresh(ref))
      let s1 = unify(typ, t.Fun(t, r, u), ref, path)
      let env =
        env_apply(s1, env)
        |> dict.insert(arg, Scheme([], apply(s1, t)))
      let s2 =
        do_infer(env, body, apply(s1, u), apply_effects(s1, r), ref, [0, ..path])
      compose(s2, s1)
    }
    ir.Apply(func, arg) -> {
      let t = t.Unbound(fresh(ref))
      // just point path to typ at top of do_infer but need to check map for errors separatly
      // unify with self needed to add to type dictionary, not problem with inference jm
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
    ir.Variable(x) ->
      case dict.get(env, x) {
        Ok(scheme) -> {
          let t = instantiate(scheme, ref)
          unify(typ, t, ref, path)
        }
        Error(Nil) ->
          Infered(
            sub.none(),
            dictx.singleton(
              list.reverse(path),
              Error(unification.MissingVariable(x)),
            ),
            dict.new(),
          )
      }
    ir.Let(x, value, then) -> {
      let t = t.Unbound(fresh(ref))
      let s1 = do_infer(env, value, t, eff, ref, [0, ..path])
      let scheme = generalise(env_apply(s1, env), apply(s1, t))
      let env = env_apply(s1, dict.insert(env, x, scheme))
      let s2 =
        do_infer(env, then, apply(s1, typ), apply_effects(s1, eff), ref, [
          1,
          ..path
        ])
      compose(s2, s1)
      // needed for path to typ to exist in state, not part of inference jm
      |> compose(unify(typ, typ, ref, path))
    }
    // Primitive
    ir.Binary(_) -> unify(typ, t.Binary, ref, path)
    ir.String(_) -> unify(typ, t.Str, ref, path)
    ir.Integer(_) -> unify(typ, t.Integer, ref, path)
    ir.Tail -> unify(typ, t.tail(ref), ref, path)
    ir.Cons -> unify(typ, t.cons(ref), ref, path)
    ir.Vacant ->
      Infered(
        sub.none(),
        dictx.singleton(list.reverse(path), Ok(typ)),
        dict.new(),
      )

    // Record
    ir.Empty -> unify(typ, t.empty(), ref, path)
    ir.Extend(label) -> unify(typ, t.extend(label, ref), ref, path)
    ir.Overwrite(label) -> unify(typ, t.overwrite(label, ref), ref, path)
    ir.Select(label) -> unify(typ, t.select(label, ref), ref, path)

    // Union
    ir.Tag(label) -> unify(typ, t.tag(label, ref), ref, path)
    ir.Case(label) -> unify(typ, t.case_(label, ref), ref, path)
    ir.NoCases -> unify(typ, t.nocases(ref), ref, path)

    // Effect
    ir.Perform(label) -> unify(typ, t.perform(label, ref), ref, path)

    ir.Handle(label) -> unify(typ, t.handle(label, ref), ref, path)

    ir.Builtin(identifier) ->
      case dict.get(stdlib.lib().0, identifier) {
        Ok(scheme) -> unify(typ, instantiate(scheme, ref), ref, path)
        Error(Nil) ->
          Infered(
            sub.none(),
            dictx.singleton(
              list.reverse(path),
              Error(
                unification.MissingVariable(string.append(
                  "Builtin: ",
                  identifier,
                )),
              ),
            ),
            dict.new(),
          )
      }
    ir.Reference(_) -> panic as "not supported in this inference"
    ir.Release(_, _, _) -> panic as "not supported in this inference"
  }
  |> compose(Infered(
    sub.none(),
    dict.new(),
    dictx.singleton(list.reverse(path), env),
  ))
}
