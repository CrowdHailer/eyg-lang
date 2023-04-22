import gleam/io
import gleam/list
import gleam/map
import gleam/set
import eygir/expression as e
import eyg/analysis/jm/error
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/env
import eyg/analysis/jm/unify
import eyg/analysis/jm/infer.{ instantiate, generalise, unify_at, extend, mono}

pub type State = #(t.Substitutions, Int, map.Map(List(Int), Result(t.Type, #(error.Reason, t.Type, t.Type))))

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

pub fn infer(sub, next, env, exp, path, type_, eff, types) {
  loop(step(sub, next, env, exp, path, type_, eff, types, Done))
}

fn step(sub, next, env, exp, path, type_, eff, types, k) {
    io.debug(exp)
   case exp {
      e.Variable(x) -> {
        case map.get(env, x) {
          Ok(scheme) ->  {
            let #(found, next) = instantiate(scheme, next)
            Cont(unify_at(type_, found, sub, next, types, path), k)
          }
          Error(Nil) -> {
            let types = map.insert(types, path, Error(#(error.MissingVariable(x), type_, t.Var(-100))))
            Cont(#(sub, next, types), k)
          }
        }
      }
      e.Apply(e1, e2) -> {
        // can't error
        let types = map.insert(types, path, Ok(type_))
        let #(arg, next) = t.fresh(next)
        use #(sub, next, types) <- step(sub, next, env, e1, [0,..path], t.Fun(arg, eff, type_), eff, types)
        use #(sub, next, types) <- step(sub, next, env, e2, [1,..path], arg, eff, types)
        Cont(#(sub, next, types), k)
      }
      e.Lambda(x, e1) -> {
        let #(arg, next) = t.fresh(next)
        let #(eff, next) = t.fresh(next)
        let #(ret, next) = t.fresh(next)
        let #(sub, next, types) = unify_at(type_, t.Fun(arg, eff, ret), sub, next, types, path) 
        let env = extend(env, x, mono(arg))
        use #(sub, next, types) <- step(sub, next, env, e1, [0, ..path], ret, eff, types)
        Cont(#(sub, next, types), k)
      }
      e.Let(x, e1, e2) -> {
        // can't error
        let types = map.insert(types, path, Ok(type_))
        let #(inner, next) = t.fresh(next)
        use #(sub, next, types) <- step(sub, next, env, e1, [0,..path], inner, eff, types)
        let env = extend(env, x, generalise(sub, env, inner))
        use #(sub, next, types) <- step(sub, next, env, e2, [1,..path], type_, eff, types)
        Cont(#(sub, next, types), k)
      }
      literal -> {
        let #(found, next) = primitive(literal, next)
        Cont(unify_at(type_, found, sub, next, types, path), k)
      }
    }

}

fn primitive(exp, next) { 
 case exp {
  e.Variable(_) | e.Apply(_,_) | e.Lambda(_,_) | e.Let(_,_,_) -> panic("not a literal")
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

  // TODO use real builtins
  e.Builtin(identifier) -> t.fresh(next)
  // _ -> todo("pull from old inference")
  
 }
}
// errors should be both wrong f and wrong arg
