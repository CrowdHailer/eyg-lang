import gleam/dict
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
}

pub type MonoType {
  TVar(Int)
  TFun(MonoType, MonoType)
  TPrimitive(Primitive)
}

pub type Primitive {
  Integer
}

pub type PolyType {
  ForAll(Set(Int), MonoType)
}

pub type Substitution =
  dict.Dict(Int, Nil)

fn empty() {
  dict.new()
}

fn compose(a, b) {
  todo
}

fn apply(sub, t) {
  todo
}

fn apply_env(sub, a) {
  todo
}

fn instantiate(scheme) {
  todo
}

fn generalize(s, t) {
  todo
}

fn unify(t1, t2) {
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
  }
  |> bind(k)
}
