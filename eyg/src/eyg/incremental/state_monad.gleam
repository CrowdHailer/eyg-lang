import gleam/io
import gleam/list
import gleam/map.{Map}
import gleam/result
import gleam/set.{Set}
import gleam/setx
import gleam/javascript
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


type State(a, env) =
  fn(env) -> #(env, a)

fn do(st: State(a, env), f: fn(a) -> State(b, env)) -> State(b, env) {
  fn(env) {
    let #(env, a) = st(env)
    let next = f(a)
    next(env)
  }
}

fn return(a: a) -> State(a, env) {
  fn(env) {
    #(env, a)
  }
}

fn run(st: State(a, env), env: env) -> a {
  st(env).1
}


// you can write:




// fn lookup(pointer) { 
//   fn(infer: Infer) {
//     #(infer, source.String("temp"))
//   }
// }


// fn w_(env, pointer) { 
//   // do_w(env, do())
//   // run the internal one
// // fn(infer) {#(infer,run(do_w(env, todo), todo))}
//   fn(infer) {
//     do_w(env, todo)(infer)
//   }
// }

// fn unbound(k) { 
//   do(fn(infer) {
//     use var <- do(fresh())
//     return(t.Unbound(var))
//   }, k)
// }

pub type Infer {
  Infer(counter: Int, source: Map(Int, source.Expression))
}

fn fresh() -> State(Int, Infer) {
  fn(infer: Infer) {
    let count = infer.counter
    #(Infer(..infer, counter: count + 1), count)
  }
}

fn w(env, pointer, k) { 
  do(fn(infer: Infer) {
    let assert Ok(exp) = map.get(infer.source, pointer)
    do_w(env, exp)(infer)
  }, k)
}


fn do_w(env, exp)  {
  case exp {
    source.Fn(x, exp1) -> {
      use tv <- do(fresh())
      use #(s1, t1) <- w(env, exp1)
      return(#(s1, t.Fun(sub.apply(s1, t.Unbound(tv)), t.Closed, t1)))      
    }
    source.String(_) -> return(#(sub.none(), t.Binary))
    _ -> todo
  }
}


// pub fn run(step, k)  {
//   case step {
//     Return(s, t) -> k(s,t)
//     Continue(p,f)-> todo
//   }
// }

// pub fn w(env, pointer, k)  {
//   Continue(pointer, fn(exp) { 
//     // TODO need k
//     run(do_w(env, exp), k)
//   })
// }

// pub type Effect {
//   Continue(Int, fn(source.Expression) -> Effect)
//   Return(sub.Substitutions, t.Term)
// }

// fn do_w(env, exp)  {
//   case exp {
//     source.Fn(x, exp1) -> {
//       use #(s1, t1) <- w(env, exp1)
//     }
//     source.String(_) -> Return(sub.none(), t.Binary)
//     _ -> todo
//   }
// }