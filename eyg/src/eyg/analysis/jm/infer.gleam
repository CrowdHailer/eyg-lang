import gleam/io
import gleam/list
import gleam/map
import gleam/set
import eyg/incremental/source as e
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/unify

fn mono(type_)  {
  #([], type_)
}

pub fn scheme_ftv(scheme) {
  let #(forall, typ) = scheme
  set.drop(t.ftv(typ), forall)
}

pub fn scheme_apply(sub, scheme) {
  let #(forall, typ) = scheme
  #(forall, t.apply(map.drop(sub, forall), typ))
}

type TypeEnv =
  map.Map(String, #(List(Int), t.Type))


// TypeEnv
pub fn env_ftv(env: TypeEnv) {
  map.fold(
    env,
    set.new(),
    fn(state, _k, scheme) { set.union(state, scheme_ftv(scheme)) },
  )
}

pub fn env_apply(sub, env) {
  map.map_values(env, fn(_k, scheme) { scheme_apply(sub, scheme) })
}

fn generalise(sub, env, t)  {
  let env = env_apply(sub, env)
  let t = t.apply(sub, t)
  let forall = set.drop(t.ftv(t), set.to_list(env_ftv(env)))
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

pub fn unify_at(type_, found, sub, next, types, ref) {
  case unify.unify(type_, found, sub, next) {
    Ok(#(s, next)) -> #(s, next, map.insert(types, ref, Ok(type_))) 
    Error(_) -> #(sub, next, map.insert(types, ref, Error(t.Missing)))
  }
}

pub fn infer(sub, next, env, source, ref, type_, eff, types, k) {
  case map.get(source, ref) {
    Error(Nil) -> k(#(sub, next, types)) 
    Ok(exp) -> case exp {
      e.Var(x) -> {
        case map.get(env, x) {
          Ok(scheme) ->  {
            let #(found, next) = instantiate(scheme, next)
            k(unify_at(type_, found, sub, next, types, ref))
          }
          Error(Nil) -> {
            let types = map.insert(types, ref, todo)
            k(#(sub, next, types))
          }
        }
      }
      e.Call(e1, e2) -> {
        // can't error
        let types = map.insert(types, ref, Ok(type_))
        let #(arg, next) = t.fresh(next)
        use #(sub, next, types) <- infer(sub, next, env, source, e1, t.Fun(arg, eff, type_), eff, types)
        use #(sub, next, types) <- infer(sub, next, env, source, e2, arg, eff, types)
        k(#(sub, next, types))
      }
      e.Fn(x, e1) -> {
        let #(arg, next) = t.fresh(next)
        let #(eff, next) = t.fresh(next)
        let #(ret, next) = t.fresh(next)
        let #(sub, next, types) = unify_at(type_, t.Fun(arg, eff, ret), sub, next, types, ref) 
        let env = extend(env, x, mono(arg))
        use #(sub, next, types) <- infer(sub, next, env, source, e1, ret, eff, types)
        k(#(sub, next, types))
      }
      e.Let(x, e1, e2) -> {
        // can't error
        let types = map.insert(types, ref, Ok(type_))
        let #(inner, next) = t.fresh(next)
        use #(sub, next, types) <- infer(sub, next, env, source, e1, inner, eff, types)
        let env = extend(env, x, generalise(sub, env, inner))
        use #(sub, next, types) <- infer(sub, next, env, source, e2, type_, eff, types)
        k(#(sub, next, types))
      }
      literal -> {
        let #(found, next) = primitive(literal, next)
        k(unify_at(type_, found, sub, next, types, ref))
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


// Can have fast inference if existing before
// reuse next and t maybe
// returning a type is good but I need to return a list of errors at least
// can't unify binary to an error

// we've got J with early return as an option
// need a building state for speed.
// Test infer not this one
// Test jm
// Write up wand