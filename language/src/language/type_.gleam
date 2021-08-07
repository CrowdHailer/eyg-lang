// TODO name typer
import gleam/io
import gleam/list

pub type Failure {
  IncorrectArity(expected: Int, given: Int)
  UnknownVariable(name: String)
  CouldNotUnify(expected: Type, given: Type)
  UnhandledVarients(remaining: List(String))
  RedundantClause(match: String)
}

pub type Type {
  // called data in Haskell, When list is empty it is an Atomic type
  // Nominal
  Data(String, List(Type))
  // If Nominal types are also Data Types maybe a Tuple should be as well.
  // Tuple(List(Type))
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
    named: List(#(String, List(String))),
  )
}

pub fn checker() {
  Typer([], 10, [])
}

pub fn get_varients(typer, type_name) {
  let Typer(named: named, ..) = typer
  list.key_find(named, type_name)
}

pub fn register_type(typer, type_name, constructors) {
  let Typer(named: named, ..) = typer
  let named = case list.key_find(named, type_name) {
    Ok(_) -> todo("Handle the error when redefining a type")
    Error(Nil) -> [#(type_name, constructors), ..named]
  }
  Ok(Typer(..typer, named: named))
}

pub fn generate_type_var(typer) {
  let Typer(next_type_var: var, ..) = typer
  #(Variable(var), Typer(..typer, next_type_var: var + 1))
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
    Function(arguments, _return) -> do_generalize(arguments, excluded, [])
    // data is already generalised
    Data(_, _) -> []
    // same for tuple??? wait for failing test
    // Tuple(_) -> []
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
    [_concrete, ..arguments] -> do_generalize(arguments, excluded, parameters)
  }
}

pub fn instantiate(poly_type, typer) {
  let PolyType(forall, type_) = poly_type
  do_instantiate(forall, type_, typer)
}

// separate type of var mono and var poly
// TODO need tests here, can we reuse resolve. probably can call in on the substitutions but we need the typer counter to keep increasing
// can't have the unification in main typer as it will undo the generalisation
fn do_instantiate(forall, type_, typer) {
  // let typer = list.fold(forall, typer, fn(i, typer) {
  //   let #(r, typer) = generate_type_var(typer)
  //   // Two variables should always unify
  //   let Ok(typer) = unify(Variable(i), r, typer)
  //   typer
  // })
  // // Need replacement that doesn't bind into the main list of sub
  // #(type_.resolve_type(_type, typer), typer)
  case forall {
    [] -> #(type_, typer)
    [i, ..rest] -> {
      let #(type_var, typer) = generate_type_var(typer)
      let type_ = case type_ {
        Data(name, arguments) -> {
          let arguments =
            do_replace_variables(arguments, Variable(i), type_var, [])
          Data(name, arguments)
        }
        Function(arguments, return) -> {
          let old = Variable(i)
          let arguments = do_replace_variables(arguments, old, type_var, [])
          let return = replace_variable(return, old, type_var)
          Function(arguments, return)
        }
      }
      do_instantiate(rest, type_, typer)
    }
  }
}

// ^^ case on type_ first then call replace(params, arguments, typer)
// params, instantiate all[Data(type_name, params), ..arguments]
// easiest might be to look up constructor and instantiate a fn.
fn do_replace_variables(arguments, old, new, accumulator) {
  case arguments {
    [] -> list.reverse(accumulator)
    [argument, ..rest] -> {
      let replacement = replace_variable(argument, old, new)
      do_replace_variables(rest, old, new, [replacement, ..accumulator])
    }
  }
}

fn replace_variable(argument, old, new) {
  case argument {
    var if var == old -> new
    Variable(_) -> argument
    Data(name, arguments) ->
      Data(name, do_replace_variables(arguments, old, new, []))
    Function(arguments, return) ->
      Function(
        do_replace_variables(arguments, old, new, []),
        replace_variable(return, old, new),
      )
  }
}

fn unify_pair(pair, typer) {
  let #(given, expected) = pair
  unify(given, expected, typer)
}

fn zip_args(given, expected) {
  case list.zip(given, expected) {
    Ok(pairs) -> Ok(pairs)
    Error(#(given, expected)) ->
      Error(IncorrectArity(expected: expected, given: given))
  }
}

pub fn unify(given, expected, typer) {
  let given = resolve_type(given, typer)
  let expected = resolve_type(expected, typer)
  let Typer(substitutions: substitutions, ..) = typer

  case given, expected {
    given, expected if given == expected -> Ok(typer)
    Variable(i), any -> {
      let substitutions = [#(i, any), ..substitutions]
      Ok(Typer(..typer, substitutions: substitutions))
    }
    any, Variable(j) -> {
      let substitutions = [#(j, any), ..substitutions]
      Ok(Typer(..typer, substitutions: substitutions))
    }
    Data(given_name, given_args), Data(expected_name, expected_args) ->
      case given_name == expected_name {
        True -> {
          try pairs = zip_args(given_args, expected_args)
          list.try_fold(pairs, typer, unify_pair)
        }
        False -> Error(CouldNotUnify(expected: expected, given: given))
      }
    Function(given_args, given_return), Function(expected_args, expected_return) -> {
      try pairs = zip_args(given_args, expected_args)
      try typer = list.try_fold(pairs, typer, unify_pair)
      unify(given_return, expected_return, typer)
    }
    _, _ -> Error(CouldNotUnify(expected: expected, given: given))
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
pub fn resolve_type(type_, typer) {
  let Typer(substitutions: substitutions, ..) = typer

  case type_ {
    Data(name, arguments) ->
      Data(name, list.map(arguments, resolve_type(_, typer)))
    // Tuple(values) -> Tuple(list.map(values, resolve_type(_, typer)))
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
