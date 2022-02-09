import gleam/list
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer/monotype as t
import eyg/typer

pub fn do_unify(t1, t2, substitutions) {
  case t1, t2 {
    t.Unbound(i), t.Unbound(j) if i == j -> Ok(substitutions)
    t.Unbound(i), _ ->
      case list.key_find(substitutions, i) {
        Ok(t1) -> do_unify(t1, t2, substitutions)
        Error(Nil) -> Ok([#(i, t2), ..substitutions])
      }
    _, t.Unbound(j) ->
      case list.key_find(substitutions, j) {
        Ok(t2) -> do_unify(t1, t2, substitutions)
        Error(Nil) -> Ok([#(j, t1), ..substitutions])
      }
    t.Native(n1), t.Native(n2) if n1 == n2 -> Ok(substitutions)
    t.Binary, t.Binary -> Ok(substitutions)
    t.Tuple(e1), t.Tuple(e2) ->
      case list.zip(e1, e2) {
        Ok(pairs) -> list.try_fold(pairs, substitutions, unify_pair)
        Error(#(c1, c2)) -> Error(typer.IncorrectArity(c1, c2))
      }
    t.Function(from1, to1), t.Function(from2, to2) -> {
      try substitutions = do_unify(from1, from2, substitutions)
      do_unify(to1, to2, substitutions)
    }
    _, _ -> Error(typer.UnmatchedTypes(t1, t2))
  }
}

fn unify(t1, t2, state: State(n)) {
  let State(substitutions: s, ..) = state
  try s = do_unify(t1, t2, s)
  //   TODO add errors here
  Ok(State(..state, substitutions: s))
}

fn unify_pair(pair, substitutions) {
  let #(t1, t2) = pair
  do_unify(t1, t2, substitutions)
}

pub fn lookup(env, label) {
  todo
}

pub fn generalise(mono, env) {
  todo("generalise")
}

pub fn instantiate(_, _) {
  todo
}

pub fn resolve(_, _) {
  todo
}

pub type State(n) {
  State(//   definetly not this
    // native_to_string: fn(n) -> String,
    next_unbound: Int, substitutions: List(#(Int, t.Monotype(n))))
}

fn fresh(state) {
  let State(next_unbound: i, ..) = state
  #(t.Unbound(i), State(..state, next_unbound: i + 1))
}

// CAN'T hold onto typer.Reason circular dependency
// definetly not string
// inconsistencies: List(#(List(Int), String)),
pub fn infer(untyped, expected) {
  let state = State(0, [])
  let scope = []
  do_infer(untyped, expected, state, scope)
}

// return just substitutions
fn do_infer(untyped, expected, state, scope) {
  let #(_, expression) = untyped
  case expression {
    e.Binary(_) ->
      case unify(expected, t.Binary, state) {
        Ok(state) -> #(Ok(expected), state)
        Error(reason) -> #(Error(reason), state)
      }
    //   e.Variable(label) -> {
    //     let schema = lookup(env, label)
    //     let monotype = instantiate(schema, substitutions)
    //     unify(expected, monotype, substitutions)
    //   }
    e.Function(p.Variable(label), body) -> {
      let #(arg, state) = fresh(state)
      let #(return, state) = fresh(state)
      case unify(expected, t.Function(arg, return), state) {
        Ok(state) ->
          do_infer(body, return, state, [#(label, #([], arg)), ..scope])
        Error(reason) -> #(Error(reason), state)
      }
    }
    //   e.Call(func, with) -> {
    //     let s = infer(func, fresh, state)
    //   }
    e.Let(p.Variable(label), value, then) -> {
      let #(u, state) = fresh(state)
      //   TODO haandle self case or variable renaming
      let #(_t, state) =
        do_infer(value, u, state, [#(label, #([], u)), ..scope])
      //   generalise with top level scope 
      let polytype = generalise(resolve(u, state), scope)
      do_infer(then, expected, state, [#(label, polytype), ..scope])
    }
  }
}
