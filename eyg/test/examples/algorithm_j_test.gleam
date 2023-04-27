import gleam/map.{get, insert as extend}
import gleam/result.{then as try_}

pub type Literal {
  Integer
  String
}

pub type Exp {
  Var(String)
  App(Exp, Exp)
  Abs(String, Exp)
  Let(String, Exp, Exp)
  Lit(Literal)
}

pub type Type {
  TInt
  // TString
  Unbound(Int)
  Fn(Type, Type)
}

pub type Scheme =
  #(List(Int), Type)

pub fn fresh(next) {
  #(Unbound(next), next + 1)
}

pub fn instantiate(scheme, next) {
  todo
}

pub fn mono(t) {
  #([], t)
}

pub fn generalise(env, t) {
  todo
}

pub fn unify(t1, t2, s) {
  do_unify([#(t1, t2)], s)
}

// s is a function from var -> t
pub fn do_unify(constraints, s) {
  // Have to try and substitute at every point because new substitutions can come into existance
  case constraints {
    [] -> Ok(s)
    [#(Unbound(i), Unbound(j)), ..constraints] -> do_unify(constraints, s)
    [#(Unbound(i), t1), ..constraints] | [#(t1, Unbound(i)), ..constraints] ->
      case map.get(s, i) {
        Ok(t2) -> do_unify([#(t1, t2), ..constraints], s)
        Error(Nil) -> do_unify(constraints, map.insert(s, i, t1))
      }
    [#(Fn(a1, r1), Fn(a2, r2)), ..cs] ->
      do_unify([#(a1, a2), #(r1, r2), ..cs], s)
    _ -> Error(Nil)
  }
}

// In exercise a type can be type err
pub fn j(env, exp, sub, next) {
  case exp {
    Var(x) -> {
      use scheme <- try_(get(env, x))
      let #(type_, next) = instantiate(scheme, next)
      Ok(#(sub, next, type_))
    }
    App(e1, e2) -> {
      use #(sub1, next, t1) <- try_(j(env, e1, sub, next))
      use #(sub2, next, t2) <- try_(j(env, e2, sub1, next))
      let #(beta, next) = fresh(next)
      use sub3 <- try_(unify(t1, Fn(t2, beta), sub2))
      Ok(#(sub, next, beta))
    }
    Abs(x, e1) -> {
      let #(beta, next) = fresh(next)
      let env1 = extend(env, x, mono(beta))
      use #(sub1, next, t1) <- try_(j(env, e1, sub, next))
      Ok(#(sub1, next, Fn(beta, t1)))
    }
    Let(x, e1, e2) -> {
      use #(sub1, next, t1) <- try_(j(env, e1, sub, next))
      // generalise needs sub applied tot1
      let env1 = extend(env, x, generalise(env, t1))
      use #(sub2, next, t2) <- try_(j(env, e2, sub1, next))
    }
    Lit(l) -> todo
  }
}
