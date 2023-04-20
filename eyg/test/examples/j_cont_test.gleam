import gleam/io
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
    TString
    Unbound(Int)
    Fn(Type,Type)
    TErr(String)
}

pub type Scheme = #(List(Int), Type)

pub fn fresh(next)  {
    #(Unbound(next), next + 1)
}

pub fn instantiate(scheme, next)  {
    todo
}

pub fn mono(t)  {
    #([], t)
}

pub fn generalise(env, t)  {
    todo
}

pub fn unify(t1, t2, s)  {
    do_unify([#(t1, t2)], s)   
}

// s is a function from var -> t
pub fn do_unify(constraints, s)  {
    // Have to try and substitute at every point because new substitutions can come into existance
    case constraints {
        [] -> Ok(s)
        [#(Unbound(i), Unbound(j)), ..constraints] -> do_unify(constraints, s)
        [#(Unbound(i), t1), ..constraints] | [#(t1, Unbound(i)), ..constraints] -> case map.get(s, i) {
            Ok(t2) -> do_unify([#(t1, t2),..constraints], s) 
            Error(Nil) -> do_unify(constraints, map.insert(s, i, t1))
        }
        [#(Fn(a1, r1), Fn(a2, r2)), ..cs] -> do_unify([#(a1, a2), #(r1, r2), ..cs], s)
        _ -> Error(Nil)
    }
}



pub type Run {
    Done(#(map.Map(Int, Type), Int, #(List(Int), Type)))
    Continue(#(map.Map(Int, Type), Int,  #(List(Int), Type)), fn(#(map.Map(Int, Type), Int, #(List(Int), Type))) -> Run)
}

// J gi
// In exercise a type can be type err
// If we ignore unification with error
// let a = 1(2)
// let b = a
// let c = a
// 
// f(x)
// f String -> Int
// x Error
// Int
// unify(string -> int, fn(err -> beta))
// int
// I think there is a version of next where we track id -> it replaces path
// incremental id and offset id are not the same thing at all.

// Follow id of node -> need free and and types in scope

// let's do j with effects and follow BUT the id's are NOT unique i.e. the types depend on the environment.
// let's try global inference and see if it's faster
pub fn step(env, exp, sub, next, path, k) {
    case exp {
        Var(x) -> {
            let scheme =  result.unwrap(get(env, x), #([], TErr("missing var")))
            let #(type_, next) = instantiate(scheme, next)
            Continue(#(sub, next, #(path,type_)), k)
        }
        App(e1, e2) -> {
            use #(sub1, next, #(_, t1)) <- step(env, e1, sub, next, [0,..path])
            use #(sub2, next, #(_, t2)) <- step(env, e2, sub1, next, [1,..path])
            let #(beta, next) = fresh(next)
            // returns t error
            let sub3 = case unify(t1, Fn(t2, beta), sub2) {
                Ok(sub3) -> sub3
                // TODO record error
                Error(_) -> sub
            }
            // let assert Ok(sub3) = 
            Continue(#(sub3, next, #(path,beta)), k)
        }
        Abs(x, e1) -> {
            let #(beta, next) = fresh(next)
            let env1 = extend(env, x, mono(beta))
            use #(sub1, next, #(_, t1)) <- step(env1, e1, sub, next, [0,..path])
            Continue(#(sub1, next, #(path,Fn(beta, t1))), k)
        }
        Let(x, e1, e2) -> {
            use #(sub1, next, #(_, t1)) <- step(env, e1, sub, next, [0,..path])
            // generalise needs sub applied tot1
            let env1 = extend(env, x, generalise(env, t1))
            use #(sub2, next, #(_, t2)) <- step(env, e2, sub1, next, [1,..path])
            Continue(#(sub2, next, #(path,t2)), k)
        }
        Lit(Integer) -> Continue(#(sub, next, #(path,TInt)), k)
        Lit(String) -> Continue(#(sub, next, #(path,TString)), k)
    }
    
}
pub fn loop(run)  {
    case run {
        Done(r) -> r
        Continue(r, k) -> {
            io.debug(r)
            loop(k(r))
            }
    }
}

pub fn j(env, exp, sub, next)  {
    loop(step(env, exp, sub, next, [], Done))
}

pub fn demo(items, k)  {
    case items {
        [] -> k("done") 
        [g, ..rest] -> demo(rest, fn(x) {
            // io.debug(g)
            g + 1
            k(x)
        })
    }
}

pub fn demo2(items, k)  {
    case items {
        [] -> k("done") 
        [g, ..rest] -> {
            use x <- demo2(rest)
            // io.debug(g)
            g + 1
            k(x)
        }
    }
}

// use twice makes reference to demo3, that blows the stack. Document this
// TODO plinth library
pub fn demo3(items, k)  {
    case items {
        [] -> k("done") 
        [g, ..rest] -> {
            use x <- demo3(rest)
            use y <- demo3(rest)

            // io.debug(g)
            g + 1
            k(x)
        }
    }
}
pub fn order_test()  {
    j(map.new(), App(Lit(Integer),Lit(String)), map.new(), 0)
    |> io.debug
    todo
}