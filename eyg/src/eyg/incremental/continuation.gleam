import gleam/io
import gleam/list
import gleam/map.{Map}
import gleam/result
import gleam/set.{Set}
import gleam/setx
import gleam/javascript
import eygir/expression as e

// TODO source -> ref
import eyg/analysis/typ as t
import eyg/analysis/substitutions as sub
import eyg/analysis/scheme.{Scheme}
import eyg/analysis/unification
import eyg/incremental/source
import eyg/analysis/env
import eyg/incremental/inference
import eyg/incremental/cursor
import plinth/javascript/map as mutable_map

// type Continuation(arg, ret) =
//   fn(fn(arg) -> ret) -> ret

// fn do(st: Continuation(a, r), f: fn(r) -> Continuation(a1, r2)) -> Continuation(a1, r2) {
//   fn(env) {
//     let #(env, a) = st(env)
//     let next = f(a)
//     next(env)
//   }
// }
// TODO continuation monad

pub fn do(arg, k) {
    // separate Cont from all other effects
    case arg {
        Push(env, exp) -> {
            cache_lookup
            // call do(push()) = > infer
        } 
    }
}

pub fn run() {
    todo
}



pub fn step(env, exp) {
    case exp {
        e.Apply(e1, e2) -> {
            use #(s1, t1) <- do(push(env, e1))
            use #(s2, t2) <- do(push(env.apply(s1, env), e2))
            let tv = t.Unbound(0)
            let ref = todo
            use s3 <- result.then(unification.unify(sub.apply(s2, t1), t.Fun(t2, t.Closed, tv), ref))
            Ok(#(sub.compose(sub.compose(s3, s2), s2), sub.apply(s3, tv)))
        }
        e.Integer(_) -> Ok(#(sub.none(), t.Integer))
        _ -> todo
    }
}