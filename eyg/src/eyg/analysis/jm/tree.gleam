import eyg/analysis/jm/env
import eyg/analysis/jm/error
import eyg/analysis/jm/infer.{builtins, extend, generalise, instantiate, mono}
import eyg/analysis/jm/type_ as t
import eygir/expression as e
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
  case exp {
    e.Variable(x) -> fetch(acc, rev, env, x, type_, envs, k)
    e.Apply(e1, e2) -> {
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
    e.Lambda(x, e1) -> {
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
    e.Let(x, e1, e2) -> {
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
    e.Builtin(x) -> fetch(acc, rev, builtins(), x, type_, envs, k)
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
    e.Variable(_)
    | e.Apply(_, _)
    | e.Lambda(_, _)
    | e.Let(_, _, _)
    | e.Builtin(_) -> panic as "not a literal"

    e.Reference(_) -> panic as "not implemented in this type checker"
    e.NamedReference(_, _) -> panic as "not implemented in this type checker"

    e.Binary(_) -> #(t.Binary, next)
    e.Str(_) -> #(t.String, next)
    e.Integer(_) -> #(t.Integer, next)

    e.Tail -> t.tail(next)
    e.Cons -> t.cons(next)
    e.Vacant -> t.fresh(next)

    // Record
    e.Empty -> t.empty(next)
    e.Extend(label) -> t.extend(label, next)
    e.Overwrite(label) -> t.overwrite(label, next)
    e.Select(label) -> t.select(label, next)

    // Union
    e.Tag(label) -> t.tag(label, next)
    e.Case(label) -> t.case_(label, next)
    e.NoCases -> t.nocases(next)

    // Effect
    e.Perform(label) -> t.perform(label, next)
    e.Handle(label) -> t.handle(label, next)
    // TODO actual shallow type checking
    e.Shallow(label) -> t.handle(label, next)
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
