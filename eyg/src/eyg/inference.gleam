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

pub fn do_free_in_type(t, substitutions, set) {
  case t {
    t.Unbound(i) ->
      case list.key_find(substitutions, i) {
        Ok(t) -> do_free_in_type(t, substitutions, set)
        Error(Nil) -> push_new(i, set)
      }
    t.Native(_) | t.Binary -> set
    // Tuple
    // Row
    t.Function(from, to) -> {
      let set = do_free_in_type(from, substitutions, set)
      do_free_in_type(to, substitutions, set)
    }
  }
}

pub fn free_in_type(t, substitutions) {
  do_free_in_type(t, substitutions, [])
}

fn push_new(item: a, set: List(a)) -> List(a) {
  case list.find(set, item) {
    Ok(_) -> set
    Error(Nil) -> [item, ..set]
  }
}

fn is_not_free_in_env(i, substitutions, env) {
  // TOODO smart filter or stateful env
  True
}

pub fn generalise(mono, substitutions, env) {
  let type_params =
    free_in_type(mono, substitutions)
    |> list.filter(fn(i) { is_not_free_in_env(i, substitutions, env) })
  //   todo("generalise")
  //   Hmm have Native(Letter) in the type and list of strings in the parameters
  // can't be new numbers
  // Dont need to be named can just use initial i's discovered
  #(type_params, mono)
}

pub fn instantiate(poly, _) {
  // same as resolve with map of new vars
  let #([], mono) = poly
  mono
}

pub fn do_resolve(t, substitutions) {
  // This has an occurs in thing
  t.resolve(t, substitutions)
  //   case t {
  //     t.Unbound(i) ->
  //       case list.key_find(substitutions, i) {
  //         Ok(t) -> do_resolve(t, substitutions)
  //         Error(Nil) -> t
  //       }
  //     Native(_) | Binary(_) -> t
  //   }
}

pub fn resolve(t, state) {
  let State(substitutions: substitutions, ..) = state
  do_resolve(t, substitutions)
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

    e.Function(p.Variable(label), body) -> {
      let #(arg, state) = fresh(state)
      let #(return, state) = fresh(state)
      case unify(expected, t.Function(arg, return), state) {
        Ok(state) ->
          do_infer(body, return, state, [#(label, #([], arg)), ..scope])
        Error(reason) -> #(Error(reason), state)
      }
    }
    e.Call(func, with) -> {
      let #(arg, state) = fresh(state)
      let #(_t, state) = do_infer(func, t.Function(arg, expected), state, scope)
      do_infer(with, arg, state, scope)
    }

    e.Let(p.Variable(label), value, then) -> {
      let #(u, state) = fresh(state)
      //   TODO haandle self case or variable renaming
      let #(_t, state) =
        do_infer(value, u, state, [#(label, #([], u)), ..scope])
      //   generalise with top level scope 
      //   Don't need generalize
      let polytype = generalise(u, state.substitutions, scope)
      do_infer(then, expected, state, [#(label, polytype), ..scope])
    }
    e.Variable(label) ->
      case list.key_find(scope, label) {
        Ok(polytype) -> {
          let monotype = instantiate(polytype, state.substitutions)
          case unify(expected, monotype, state) {
            Ok(state) -> #(Ok(expected), state)
            Error(reason) -> #(Error(reason), state)
          }
        }
        Error(Nil) -> #(Error(typer.UnknownVariable(label)), state)
      }
  }
}
