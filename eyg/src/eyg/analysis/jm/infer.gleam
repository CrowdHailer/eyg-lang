import gleam/io
import gleam/list
import gleam/map
import gleam/set
import eyg/incremental/source as e
import eyg/analysis/jm/error
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/env
import eyg/analysis/jm/unify

pub fn mono(type_)  {
  #([], type_)
}

// reference substitution env and type.
// causes circular dependencies to move to any other file
pub fn generalise(sub, env, t)  {
  let env = env.apply(sub, env)
  let t = t.apply(sub, t)
  let forall = set.drop(t.ftv(t), set.to_list(env.ftv(env)))
  #(set.to_list(forall), t)
}

pub fn instantiate(scheme, next) {
  let #(forall, type_) = scheme
  let s = list.index_map(forall, fn(i, old) { #(old, t.Var(next + i))})
  |> map.from_list()
  let next = next + list.length(forall)
  let type_ = t.apply(s, type_)
  #(type_, next)
}


pub fn extend(env, label, scheme) { 
  map.insert(env, label, scheme)
}

pub fn unify_at(type_, found, sub, next, types, ref) {
  case unify.unify(type_, found, sub, next) {
    Ok(#(s, next)) -> #(s, next, map.insert(types, ref, Ok(type_))) 
    Error(reason) -> #(sub, next, map.insert(types, ref, Error(#(reason, type_, found))))
  }
}

pub type State = #(t.Substitutions, Int, map.Map(Int, Result(t.Type, #(error.Reason, t.Type, t.Type))))

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
