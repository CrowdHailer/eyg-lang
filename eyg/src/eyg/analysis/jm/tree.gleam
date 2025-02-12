import eyg/analysis/jm/env
import eyg/analysis/jm/error
import eyg/analysis/jm/infer.{builtins, extend, generalise, instantiate, mono}
import eyg/analysis/jm/type_ as t
import eygir/annotated as a
import gleam/dict

pub type State =
  #(
    t.Substitutions,
    Int,
    dict.Dict(List(Int), Result(t.Type, #(error.Reason, t.Type, t.Type))),
  )

pub type Envs =
  dict.Dict(List(Int), env.Env)

pub type Run {
  Cont(State, Envs, fn(State, Envs) -> Run)
  Done(State, Envs)
}

// this is required to make the infer function tail recursive
pub fn loop(run) {
  case run {
    Done(state, envs) -> #(state, envs)
    Cont(state, envs, k) -> loop(k(state, envs))
  }
}

pub fn infer_env(exp, type_, eff, env, sub, next) {
  let types = dict.new()
  // Switching path to integer took ~ 20% off the inference time 600ms to 500ms for 6000 nodes
  let path = []
  let acc = #(sub, next, types)
  let envs = dict.new()
  loop(step(acc, env, envs, exp, path, type_, eff, Done))
}

pub fn infer(exp, type_, eff) {
  infer_env(exp, type_, eff, dict.new(), dict.new(), 0)
}

fn step(acc, env, envs, exp, rev, type_, eff, k) -> Run {
  let #(exp, _meta) = exp
  case exp {
    a.Variable(x) -> fetch(acc, rev, env, x, type_, envs, k)
    a.Apply(e1, e2) -> {
      // can't error
      let #(sub, next, types) = acc
      let types = dict.insert(types, rev, Ok(type_))
      let #(arg, next) = t.fresh(next)
      let acc = #(sub, next, types)
      let func = t.Fun(arg, eff, type_)
      use acc, envs <- step(acc, env, envs, e1, [0, ..rev], func, eff)
      use acc, envs <- step(acc, env, envs, e2, [1, ..rev], arg, eff)
      Cont(acc, envs, k)
    }
    a.Lambda(x, e1) -> {
      let #(sub, next, types) = acc
      let #(arg, next) = t.fresh(next)
      let #(eff, next) = t.fresh(next)
      let #(ret, next) = t.fresh(next)
      let acc = #(sub, next, types)
      let envs = dict.insert(envs, rev, env)

      let func = t.Fun(arg, eff, ret)
      let acc = unify_at(acc, rev, type_, func)
      let env = extend(env, x, mono(arg))
      use acc, envs <- step(acc, env, envs, e1, [0, ..rev], ret, eff)
      Cont(acc, envs, k)
    }
    a.Let(x, e1, e2) -> {
      // can't error
      let #(sub, next, types) = acc
      let types = dict.insert(types, rev, Ok(type_))
      let #(inner, next) = t.fresh(next)
      let acc = #(sub, next, types)

      use acc, envs <- step(acc, env, envs, e1, [0, ..rev], inner, eff)
      let env = extend(env, x, generalise(acc.0, env, inner))
      use acc, envs <- step(acc, env, envs, e2, [1, ..rev], type_, eff)
      Cont(acc, envs, k)
    }
    a.Builtin(x) -> fetch(acc, rev, builtins(), x, type_, envs, k)
    literal -> {
      let #(sub, next, types) = acc
      let #(found, next) = primitive(literal, next)
      let acc = #(sub, next, types)
      Cont(unify_at(acc, rev, type_, found), envs, k)
    }
  }
}

fn primitive(exp, next) {
  case exp {
    a.Variable(_)
    | a.Apply(_, _)
    | a.Lambda(_, _)
    | a.Let(_, _, _)
    | a.Builtin(_) -> panic as "not a literal"

    a.Reference(_) -> panic as "not implemented in this type checker"
    a.NamedReference(_, _) -> panic as "not implemented in this type checker"

    a.Binary(_) -> #(t.Binary, next)
    a.Str(_) -> #(t.String, next)
    a.Integer(_) -> #(t.Integer, next)

    a.Tail -> t.tail(next)
    a.Cons -> t.cons(next)
    a.Vacant -> t.fresh(next)

    // Record
    a.Empty -> t.empty(next)
    a.Extend(label) -> t.extend(label, next)
    a.Overwrite(label) -> t.overwrite(label, next)
    a.Select(label) -> t.select(label, next)

    // Union
    a.Tag(label) -> t.tag(label, next)
    a.Case(label) -> t.case_(label, next)
    a.NoCases -> t.nocases(next)

    // Effect
    a.Perform(label) -> t.perform(label, next)
    a.Handle(label) -> t.handle(label, next)
  }
}

pub fn unify_at(acc, path, expected, found) {
  let #(sub, next, types) = acc
  infer.unify_at(expected, found, sub, next, types, path)
}

pub fn fetch(acc, path, env, x, type_, envs, k) {
  case dict.get(env, x) {
    Ok(scheme) -> {
      let #(sub, next, types) = acc
      let #(found, next) = instantiate(scheme, next)
      let acc = #(sub, next, types)
      Cont(unify_at(acc, path, type_, found), envs, k)
    }
    Error(Nil) -> {
      let #(sub, next, types) = acc
      let #(unmatched, next) = t.fresh(next)
      let types =
        dict.insert(
          types,
          path,
          Error(#(error.MissingVariable(x), type_, unmatched)),
        )
      let acc = #(sub, next, types)
      Cont(acc, envs, k)
    }
  }
}
