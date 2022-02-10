import gleam/io
import gleam/list
import gleam/pair
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer/monotype as t
import eyg/typer

pub fn do_unify(pair, substitutions) {
  let #(t1, t2) = pair
  case t1, t2 {
    t.Unbound(i), t.Unbound(j) if i == j -> Ok(substitutions)
    t.Unbound(i), _ ->
      case list.key_find(substitutions, i) {
        Ok(t1) -> do_unify(#(t1, t2), substitutions)
        Error(Nil) -> Ok([#(i, t2), ..substitutions])
      }
    _, t.Unbound(j) ->
      case list.key_find(substitutions, j) {
        Ok(t2) -> do_unify(#(t1, t2), substitutions)
        Error(Nil) -> Ok([#(j, t1), ..substitutions])
      }
    t.Native(n1), t.Native(n2) if n1 == n2 -> Ok(substitutions)
    t.Binary, t.Binary -> Ok(substitutions)
    t.Tuple(e1), t.Tuple(e2) ->
      case list.zip(e1, e2) {
        Ok(pairs) -> list.try_fold(pairs, substitutions, do_unify)
        Error(#(c1, c2)) -> Error(typer.IncorrectArity(c1, c2))
      }
    t.Function(from1, to1), t.Function(from2, to2) -> {
      try substitutions = do_unify(#(from1, from2), substitutions)
      do_unify(#(to1, to2), substitutions)
    }
    _, _ -> Error(typer.UnmatchedTypes(t1, t2))
  }
}

fn unify(t1, t2, state: State(n)) {
  let State(substitutions: s, ..) = state
  try s = do_unify(#(t1, t2), s)
  //   TODO add errors here
  Ok(State(..state, substitutions: s))
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

pub fn do_free_in_polytype(poly, substitutions) {
  let #(quantifiers, mono) = poly
  difference(free_in_type(mono, substitutions), quantifiers)
}

pub fn do_free_in_env(env, substitutions, set) {
  case env {
    [] -> set
    [#(_, polytype), ..env] -> {
      let set = union(do_free_in_polytype(polytype, substitutions), set)
      do_free_in_env(env, substitutions, set)
    }
  }
}

pub fn free_in_env(env, substitutions) {
  do_free_in_env(env, substitutions, [])
}

// TODO smart filter or stateful env
// |> list.filter(fn(i) { is_not_free_in_env(i, substitutions, env) })
//   Hmm have Native(Letter) in the type and list of strings in the parameters
// can't be new numbers
// Dont need to be named can just use initial i's discovered
pub fn generalise(mono, substitutions, env) {
  let type_params =
    difference(
      free_in_type(mono, substitutions),
      free_in_env(env, substitutions),
    )
  #(type_params, mono)
}

pub fn instantiate(poly, state) {
  let #(forall, mono) = poly
  let #(substitutions, state) =
    list.map_state(
      forall,
      state,
      fn(i, state) {
        let #(tj, state) = fresh(state)
        #(#(i, tj), state)
      },
    )
  let t = do_resolve(mono, substitutions)
  #(t, state)
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
    e.Tuple(elements) -> {
      let #(with_type, state) =
        list.map_state(
          elements,
          state,
          fn(e, state) {
            let #(u, state) = fresh(state)
            #(#(e, u), state)
          },
        )
      case unify(expected, t.Tuple(list.map(with_type, pair.second)), state) {
        Ok(state) -> #(Ok(expected), state)
        Error(reason) -> #(Error(reason), state)
      }
      list.map_state(with_type, fn(with_type, state) {
        let #(element, expected) = 
      })
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
      let value_scope = [#(label, #([], u)), ..scope]
      let #(_t, state) = do_infer(value, u, state, value_scope)
      let polytype = generalise(u, state.substitutions, scope)
      do_infer(then, expected, state, [#(label, polytype), ..scope])
    }
    e.Variable(label) ->
      case list.key_find(scope, label) {
        Ok(polytype) -> {
          let #(monotype, state) = instantiate(polytype, state)
          case unify(expected, monotype, state) {
            Ok(state) -> #(Ok(expected), state)
            Error(reason) -> #(Error(reason), state)
          }
        }
        Error(Nil) -> #(Error(typer.UnknownVariable(label)), state)
      }
  }
}

// Set
fn push_new(item: a, set: List(a)) -> List(a) {
  case list.find(set, item) {
    Ok(_) -> set
    Error(Nil) -> [item, ..set]
  }
}

fn difference(items: List(a), excluded: List(a)) -> List(a) {
  do_difference(items, excluded, [])
}

fn do_difference(items, excluded, accumulator) {
  case items {
    [] -> list.reverse(accumulator)
    [next, ..items] ->
      case list.find(excluded, next) {
        Ok(_) -> do_difference(items, excluded, accumulator)
        Error(_) -> push_new(next, accumulator)
      }
  }
}

fn union(new: List(a), existing: List(a)) -> List(a) {
  case new {
    [] -> existing
    [next, ..new] -> {
      let existing = push_new(next, existing)
      union(new, existing)
    }
  }
}
