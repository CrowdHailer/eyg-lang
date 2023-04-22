import gleam/io
import gleam/list
import gleam/map
import gleam/set
import eyg/incremental/source as e
import eyg/analysis/jm/error
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/env
import eyg/analysis/jm/unify

fn mono(type_)  {
  #([], type_)
}

// reference substitution env and type.
// causes circular dependencies to move to any other file
fn generalise(sub, env, t)  {
  let env = env.apply(sub, env)
  let t = t.apply(sub, t)
  let forall = set.drop(t.ftv(t), set.to_list(env.ftv(env)))
  #(set.to_list(forall), t)
}

fn instantiate(scheme, next) {
  let #(forall, type_) = scheme
  let s = list.index_map(forall, fn(i, old) { #(old, t.Var(next + i))})
  |> map.from_list()
  let next = next + list.length(forall)
  let type_ = t.apply(s, type_)
  #(type_, next)
}


fn extend(env, label, scheme) { 
  map.insert(env, label, scheme)
}

fn unify_at(type_, found, sub, next, types, ref) {
  case unify.unify(type_, found, sub, next) {
    Ok(#(s, next)) -> #(s, next, map.insert(types, ref, Ok(type_))) 
    Error(reason) -> #(sub, next, map.insert(types, ref, Error(#(reason, type_, found))))
  }
}

type State = #(t.Substitutions, Int, map.Map(Int, Result(t.Type, #(error.Reason, t.Type, t.Type))))

type Run {
  Cont(State, fn(State) -> Run)
  Done(State)
}

pub fn infer(sub, next, env, source, ref, type_, eff, types) {
  loop(step(sub, next, env, source, ref, type_, eff, types, Done))
}

fn loop(run) {
  case run {
    Done(state) -> state
    Cont(state, k) -> loop(k(state))
  }
}

fn step(sub, next, env, source, ref, type_, eff, types, k) {
  case map.get(source, ref) {
    Error(Nil) -> Cont(#(sub, next, types), k) 
    Ok(exp) -> case exp {
      e.Var(x) -> {
        case map.get(env, x) {
          Ok(scheme) ->  {
            let #(found, next) = instantiate(scheme, next)
            Cont(unify_at(type_, found, sub, next, types, ref), k)
          }
          Error(Nil) -> {
            let types = map.insert(types, ref, Error(#(error.MissingVariable(x), type_, t.Var(-100))))
            Cont(#(sub, next, types), k)
          }
        }
      }
      e.Call(e1, e2) -> {
        // can't error
        let types = map.insert(types, ref, Ok(type_))
        let #(arg, next) = t.fresh(next)
        use #(sub, next, types) <- step(sub, next, env, source, e1, t.Fun(arg, eff, type_), eff, types)
        use #(sub, next, types) <- step(sub, next, env, source, e2, arg, eff, types)
        Cont(#(sub, next, types), k)
      }
      e.Fn(x, e1) -> {
        let #(arg, next) = t.fresh(next)
        let #(eff, next) = t.fresh(next)
        let #(ret, next) = t.fresh(next)
        let #(sub, next, types) = unify_at(type_, t.Fun(arg, eff, ret), sub, next, types, ref) 
        let env = extend(env, x, mono(arg))
        use #(sub, next, types) <- step(sub, next, env, source, e1, ret, eff, types)
        Cont(#(sub, next, types), k)
      }
      e.Let(x, e1, e2) -> {
        // can't error
        let types = map.insert(types, ref, Ok(type_))
        let #(inner, next) = t.fresh(next)
        use #(sub, next, types) <- step(sub, next, env, source, e1, inner, eff, types)
        let env = extend(env, x, generalise(sub, env, inner))
        use #(sub, next, types) <- step(sub, next, env, source, e2, type_, eff, types)
        Cont(#(sub, next, types), k)
      }
      literal -> {
        let #(found, next) = primitive(literal, next)
        Cont(unify_at(type_, found, sub, next, types, ref), k)
      }
    }
  }
}

fn primitive(exp, next) { 
 case exp {
  e.Var(_) | e.Call(_,_) | e.Fn(_,_) | e.Let(_,_,_) -> panic("not a literal")
  e.String(_) -> #(t.String, next)
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

  // TODO use real builtins
  e.Builtin(identifier) -> t.fresh(next)
  // _ -> todo("pull from old inference")
  
 }
}
// errors should be both wrong f and wrong arg


