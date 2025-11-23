import gleam/dict
import gleam/result
import gleam/set.{type Set}
import type_systems/counter_result.{bind, ok, stop}

fn fresh(k) {
  use i <- counter_result.fresh()
  ok(TVar(i))
  |> bind(k)
}

pub fn lookup(assumptions, variable) {
  case dict.get(assumptions, variable) {
    Ok(value) -> ok(value)
    Error(Nil) -> stop("no var")
  }
}

pub type Expression {
  Var(String)
  App(Expression, Expression)
  Abs(String, Expression)
  Let(String, Expression, Expression)
  Constant(Primitive)
}

pub type Primitive {
  Integer
}

pub type MonoType {
  TVar(Int)
  TFun(MonoType, MonoType)
  TPrimitive(TPrimitive)
}

pub type TPrimitive {
  TInteger
}

pub type PolyType {
  ForAll(Set(Int), MonoType)
}

pub type Substitution =
  dict.Dict(Int, MonoType)

fn empty() {
  dict.new()
}

fn compose(a, b) -> Substitution {
  todo
}

fn apply(s, t) {
  case t {
    // This assumes subs are already all applied
    TVar(i) -> dict.get(s, i) |> result.unwrap(t)
    TFun(t1, t2) -> TFun(apply(s, t1), apply(s, t2))
    primitive -> primitive
  }
}

fn apply_env(sub, a) {
  todo
}

fn occurs(i, t) {
  case t {
    TVar(j) -> i == j
    TFun(t1, t2) -> occurs(i, t1) || occurs(i, t2)
    _ -> False
  }
}

fn unify(t1, t2) -> counter_result.CounterResult(Substitution, String) {
  case t1, t2 {
    TVar(i), TVar(j) if i == j -> ok(empty())
    TVar(i), t | t, TVar(i) ->
      case occurs(i, t) {
        True -> stop("")
        False -> ok(dict.from_list([#(i, t)]))
      }
    TFun(t1, t2), TFun(u1, u2) -> {
      use s1 <- bind(unify(t1, u1))
      use s2 <- bind(unify(apply(s1, t2), apply(s1, u2)))
      ok(compose(s1, s2))
    }
    TPrimitive(p), TPrimitive(q) if p == q -> ok(empty())
    _, _ -> stop("")
  }
}

fn instantiate(scheme) {
  todo
}

fn generalize(s, t) {
  todo
}

// pub fn u(a, e, k) {
//   bind(w(a, e), k)
// }

pub fn w(a, exp, k) {
  case exp {
    Var(x) -> {
      use scheme <- bind(lookup(a, x))
      ok(#(empty(), instantiate(scheme)))
    }
    App(e1, e2) -> {
      use #(s1, t1) <- w(a, e1)
      use #(s2, t2) <- w(apply_env(s1, a), e2)
      use beta <- fresh()
      use v <- bind(unify(apply(s2, t1), TFun(t2, beta)))
      ok(#(compose(v, compose(s2, s1)), apply(v, beta)))
    }
    Abs(x, e) -> {
      use beta <- fresh()
      let a = dict.insert(a, x, ForAll(set.new(), beta))
      use #(s1, t2) <- w(a, e)
      ok(#(s1, TFun(apply(s1, beta), t2)))
    }
    Let(x, e1, e2) -> {
      use #(s1, t1) <- w(a, e1)
      let a = dict.insert(a, x, generalize(s1, t1))
      use #(s2, t2) <- w(apply_env(s1, a), e2)
      ok(#(compose(s2, s1), t2))
    }
    Constant(Integer) -> ok(#(empty(), TPrimitive(TInteger)))
  }
  |> bind(k)
}

// Top down
pub fn m(env, exp, type_) -> counter_result.CounterResult(Substitution, String) {
  case exp {
    Constant(Integer) -> unify(type_, TPrimitive(TInteger))
    Var(x) -> {
      use scheme <- bind(lookup(env, x))
      let t = instantiate(scheme)
      unify(type_, t)
    }
    Abs(x, e) -> {
      use beta1 <- fresh()
      use beta2 <- fresh()
      use s1 <- bind(unify(type_, TFun(beta1, beta2)))
      let env = apply_env(s1, dict.insert(env, x, ForAll(set.new(), beta1)))
      use s2 <- bind(m(env, e, apply(s1, beta2)))
      ok(compose(s2, s1))
    }
    App(e1, e2) -> {
      use beta <- fresh()
      use s1 <- bind(m(env, e1, TFun(beta, type_)))
      use s2 <- bind(m(apply_env(s1, env), e2, apply(s1, beta)))
      ok(compose(s2, s1))
    }
    Let(x, e1, e2) -> {
      use beta <- fresh()
      use s1 <- bind(m(env, e1, beta))
      let scheme = generalize(s1, apply(s1, beta))
      let env = apply_env(s1, env) |> dict.insert(x, scheme)
      use s2 <- bind(m(env, e2, apply(s1, type_)))
      ok(compose(s2, s1))
    }
  }
}
