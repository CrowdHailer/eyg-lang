import gleam/map
import eygir/expression as e
import eyg/analysis/jm/error
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/infer.{builtins, extend, generalise, instantiate, mono}

pub type State =
  #(
    t.Substitutions,
    Int,
    map.Map(List(Int), Result(t.Type, #(error.Reason, t.Type, t.Type))),
  )

pub type Run {
  Cont(State, fn(State) -> Run)
  Done(State)
}

// this is required to make the infer function tail recursive
pub fn loop(run) {
  case run {
    Done(state) -> state
    Cont(state, k) -> loop(k(state))
  }
}

pub fn infer_env(exp, type_, eff, env) {
  let sub = map.new()
  let next = 0
  let types = map.new()
  // Switching path to integer took ~ 20% off the inference time 600ms to 500ms for 6000 nodes
  let path = []
  let acc = #(sub, next, types)
  loop(step(acc, env, exp, path, type_, eff, Done))
}

pub fn infer(exp, type_, eff) {
  infer_env(exp, type_, eff, map.new())
}

fn step(acc, env, exp, path, type_, eff, k) {
  case exp {
    e.Variable(x) -> fetch(acc, path, env, x, type_, k)
    e.Apply(e1, e2) -> {
      // can't error
      let #(sub, next, types) = acc
      let types = map.insert(types, path, Ok(type_))
      let #(arg, next) = t.fresh(next)
      let acc = #(sub, next, types)
      let func = t.Fun(arg, eff, type_)
      use acc <- step(acc, env, e1, [0, ..path], func, eff)
      use acc <- step(acc, env, e2, [1, ..path], arg, eff)
      Cont(acc, k)
    }
    e.Lambda(x, e1) -> {
      let #(sub, next, types) = acc
      let #(arg, next) = t.fresh(next)
      let #(eff, next) = t.fresh(next)
      let #(ret, next) = t.fresh(next)
      let acc = #(sub, next, types)

      let func = t.Fun(arg, eff, ret)
      let acc = unify_at(acc, path, type_, func)
      let env = extend(env, x, mono(arg))
      use acc <- step(acc, env, e1, [0, ..path], ret, eff)
      Cont(acc, k)
    }
    e.Let(x, e1, e2) -> {
      // can't error
      let #(sub, next, types) = acc
      let types = map.insert(types, path, Ok(type_))
      let #(inner, next) = t.fresh(next)
      let acc = #(sub, next, types)

      use acc <- step(acc, env, e1, [0, ..path], inner, eff)
      let env = extend(env, x, generalise(acc.0, env, inner))
      use acc <- step(acc, env, e2, [1, ..path], type_, eff)
      Cont(acc, k)
    }
    e.Builtin(x) -> fetch(acc, path, builtins(), x, type_, k)
    literal -> {
      let #(sub, next, types) = acc
      let #(found, next) = primitive(literal, next)
      let acc = #(sub, next, types)
      Cont(unify_at(acc, path, type_, found), k)
    }
  }
}

fn primitive(exp, next) {
  case exp {
    e.Variable(_)
    | e.Apply(_, _)
    | e.Lambda(_, _)
    | e.Let(_, _, _)
    | e.Builtin(_) -> panic("not a literal")
    e.Binary(_) -> #(t.String, next)
    e.Integer(_) -> #(t.Integer, next)

    e.Tail -> t.tail(next)
    e.Cons -> t.cons(next)
    e.Vacant(_comment) -> t.fresh(next)

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
  }
}

pub fn unify_at(acc, path, expected, found) {
  let #(sub, next, types) = acc
  infer.unify_at(expected, found, sub, next, types, path)
}

pub fn fetch(acc, path, env, x, type_, k) {
  case map.get(env, x) {
    Ok(scheme) -> {
      let #(sub, next, types) = acc
      let #(found, next) = instantiate(scheme, next)
      let acc = #(sub, next, types)
      Cont(unify_at(acc, path, type_, found), k)
    }
    Error(Nil) -> {
      let #(sub, next, types) = acc
      let #(unmatched, next) = t.fresh(next)
      let types =
        map.insert(
          types,
          path,
          Error(#(error.MissingVariable(x), type_, unmatched)),
        )
      let acc = #(sub, next, types)
      Cont(acc, k)
    }
  }
}
