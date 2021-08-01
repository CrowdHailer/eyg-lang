// TODO name typer
import gleam/io
import gleam/list

pub type Type {
  // called data in Haskell, When list is empty it is an Atomic type
  Data(String, List(Type))
  Function(List(Type), Type)
  Variable(Int)
}

pub type PolyType {
  PolyType(forall: List(Int), type_: Type)
}

//   RowType(forall: Int, rows: List(#(String, Type)))
// A linear type on substitutions would ensure passed around
// TODO merge substitutions, need to keep passing next var in typer
// type checker state
pub type Typer {
  Typer(
    // typer passed as globally acumulating set, env is scoped
    substitutions: List(#(Int, Type)),
    next_type_var: Int,
  )
}

pub fn checker() {
  Typer([], 10)
}

// Need to understand the concept of free variables better.
pub fn free_variables(poly) {
  case poly {
    PolyType([], Variable(i)) -> [i]
    PolyType([], Data(_, _)) -> []
    PolyType(quantified, Function(arguments, return)) ->
      extract_free_variables(quantified, [return, ..list.reverse(arguments)])
  }
}

fn extract_free_variables(quantified, variables) {
  list.fold(
    variables,
    [],
    fn(argument, free) {
      case argument {
        Variable(x) ->
          case list.find(quantified, x) {
            Ok(_) -> free
            Error(Nil) -> push_new(x, free)
          }
        Data(_name, inner) ->
          extract_free_variables(quantified, inner)
          |> list.fold(free, push_new)
        Function(arguments, return) ->
          extract_free_variables(quantified, [return, ..arguments])
          |> list.fold(free, push_new)
      }
    },
  )
}

fn push_new(item, set) {
  case list.find(set, item) {
    Ok(_) -> set
    Error(Nil) -> [item, ..set]
  }
}

// TODO remove free variables that all already in the environment as they might get bound later
// Can I convince myself that all generalisable variables must be above the typer current counter
// Yes because the environment is passed in and not used again.
// call this fn generalise when called here.
pub fn generalised_by(type_, excluded, typer) {
  let type_ = resolve_type(type_, typer)
  let forall = case type_ {
    Function(arguments, return) -> do_generalize(arguments, excluded, [])
    // data is already generalised
    Data(_, _) -> []
    Variable(_) -> []
  }
  forall
}

fn do_generalize(arguments, excluded, parameters) {
  case arguments {
    [] -> list.reverse(parameters)
    [Variable(i), ..arguments] -> {
      let parameters = case list.find(parameters, i) {
        Ok(_) -> parameters
        Error(Nil) -> [i, ..parameters]
      }
      do_generalize(arguments, excluded, parameters)
    }
    [concrete, ..arguments] -> do_generalize(arguments, excluded, parameters)
  }
}

pub fn generate_type_var(typer) {
  let Typer(next_type_var: var, ..) = typer
  #(Variable(var), Typer(..typer, next_type_var: var + 1))
}

pub type UnificationFailure {
  UnificationFailure(
    expected: String,
    found: String
  )
}

pub fn unify(t1, t2, typer) {
  case t1, t2 {
    t1, t2 if t1 == t2 -> Ok(typer)
    Variable(i), any -> unify_variable(i, any, typer)
    any, Variable(i) -> unify_variable(i, any, typer)
    Data(n1, args1), Data(n2, args2) ->
      case n1 == n2 {
        True -> unify_all(args1, args2, typer)
        False -> {
          // stack on names too
          // io.debug(t1)
          // io.debug(t2)
          Error(UnificationFailure(expected: n2, found: n1))}
      }
    Function(args1, return1), Function(args2, return2) -> {
      try typer = unify_all(args1, args2, typer)
      unify(return1, return2, typer)
    }
    Data(name, _), Function(_, _) -> {
      Error(UnificationFailure(expected: "Function", found: name))
    }
    Function(_, _), Data(name, _) -> {
      Error(UnificationFailure(expected: name, found: "Function"))

    }
  }
  // Row(fields, variable), Row(fields, variable) ->
  // case do_shared(left, right, [], []) {
  //   #([], []) -> unify(l_var, r_var)
  //   #(only_left, only_right) -> {
  //     // Need to exit on the case of empy onlyleft and right
  //     // new_var
  //     try unify(Row(only_right, new_var), l_var, typer)
  //     try unify(Row(only_left, new_var), r_var, typer)
  //   }
  // }
}

// do_shared(left, right, shared, only_left) {
//   case left {
//     [] -> list.reverse(only_left), right, shared
//     [#(name, l_type), ..rest] -> case list.key_pop(right, name) {
//       Ok(r_type) -> todo("unify left and right") 
//       Error(Nil) -> do_shared(rest, right_but_popped, shared, [#(name, l_type), ..only_left])
//     }
//   }
// }
// TODO exhausive on guards.
// Pattern is Var(String) || Destructure || RowLookup (Does row lookup work for cases I don't think my types support union on rows.)
fn unify_variable(i, any, typer) {
  let Typer(substitutions: substitutions, ..) = typer
  case list.key_find(substitutions, i) {
    Ok(replacement) -> unify(replacement, any, typer)
    Error(Nil) ->
      case any {
        Variable(j) ->
          case list.key_find(substitutions, i) {
            Ok(replacement) -> unify(replacement, any, typer)
            _ -> {
              let substitutions = [#(i, any), ..substitutions]
              let typer = Typer(..typer, substitutions: substitutions)
              Ok(typer)
            }
          }
        // TODO occurs check
        _ -> {
          let substitutions = [#(i, any), ..substitutions]
          let typer = Typer(..typer, substitutions: substitutions)
          Ok(typer)
        }
      }
  }
}

fn unify_all(t1s, t2s, typer) {
  case t1s, t2s {
    [], [] -> Ok(typer)
    [t1, ..t1s], [t2, ..t2s] -> {
      try typer = unify(t1, t2, typer)
      unify_all(t1s, t2s, typer)
    }
    [], _ ->  Error(UnificationFailure(expected: "More arguments", found: "None"))

    _, [] -> Error(UnificationFailure(expected: "Less arguments", found: "more"))
  }
}

pub fn resolve_type(type_, typer) {
  let Typer(substitutions: substitutions, ..) = typer

  case type_ {
    Data(name, arguments) ->
      Data(name, list.map(arguments, resolve_type(_, typer)))
    Function(arguments, return) ->
      Function(
        list.map(arguments, resolve_type(_, typer)),
        resolve_type(return, typer),
      )
    Variable(i) ->
      case list.key_find(substitutions, i) {
        Ok(Variable(j)) if i == j -> type_
        Error(Nil) -> type_
        Ok(substitution) -> resolve_type(substitution, typer)
      }
  }
}
