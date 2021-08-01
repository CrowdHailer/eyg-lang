import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import language/scope
import language/type_.{
  Data, Function, IncorrectArity, PolyType, Type, Typer, Variable, generate_type_var,
  unify,
}

/// Type destructure used for let and case statements
pub type Pattern {
  Destructure(String, List(String))
  Assignment(String)
}

/// Expression tree with type information
pub type Expression(t) {
  Let(pattern: Pattern, value: #(t, Expression(t)), in: #(t, Expression(t)))
  Var(name: String)
  Binary
  Case(
    subject: #(t, Expression(t)),
    clauses: List(#(Pattern, #(t, Expression(t)))),
  )
  // Clashes with Function Type, maybe call Anonymous, Lambda
  Fn(arguments: List(#(t, String)), body: #(t, Expression(t)))
  Call(function: #(t, Expression(t)), arguments: List(#(t, Expression(t))))
}

fn push_arguments(untyped, scope, typer) {
  // TODO check double names
  let #(typed, typer) = do_argument_typing(untyped, [], typer)
  let scope = do_push_arguments(typed, scope)
  #(typed, scope, typer)
}

fn do_push_arguments(typed, scope) {
  case typed {
    [] -> scope
    [#(type_, name), ..rest] ->
      do_push_arguments(
        rest,
        scope.set_variable(scope, name, PolyType([], type_)),
      )
  }
}

fn do_argument_typing(arguments, typed, typer) {
  case arguments {
    [] -> #(list.reverse(typed), typer)
    [#(Nil, name), ..rest] -> {
      let #(type_, typer) = generate_type_var(typer)
      let typed = [#(type_, name), ..typed]
      do_argument_typing(rest, typed, typer)
    }
  }
}

fn do_typed_arguments_remove_name(
  remaining: List(#(Type, String)),
  accumulator: List(Type),
) -> List(Type) {
  case remaining {
    [] -> list.reverse(accumulator)
    [x, ..rest] -> {
      let #(typed, _name) = x
      do_typed_arguments_remove_name(rest, [typed, ..accumulator])
    }
  }
}

pub fn infer(untyped, environment) {
  do_infer(untyped, environment, type_.checker())
}

fn instantiate(poly_type, typer) {
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
  //   |> io.debug()
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

fn bind_pattern(pattern, type_, scope, typer) {
  case pattern {
    // Some mish mash of resolving needed at the right time.
    // quantified variables should never be accessed again because the should always get instantiated out.
    // Try moving the set stuff into the scope module
    // Polytype is also called a generic type
    Assignment(name) -> {
      let type_ = type_.resolve_type(type_, typer)
      let excluded: List(Int) = scope.free_variables(scope)
      let poly_type =
        PolyType(type_.generalised_by(type_, excluded, typer), type_)
      let scope = scope.set_variable(scope, name, poly_type)
      Ok(#(scope, typer))
    }
    Destructure(constructor, with) ->
      case constructor, with {
        "Function", _ -> todo("Can;t destructure function")
        constructor, assignments -> {
          io.debug("asssssssss")
          io.debug(assignments)
          try #(type_name, parameters, arguments) =
            scope.get_constructor(scope, constructor)
          io.debug("----------------")
          let #(replacements, typer) =
            generate_replacement_vars(parameters, [], typer)
          let replaced_arguments =
            replace_variables(arguments, replacements, [])
          let type_params =
            list.map(
              replacements,
              fn(pair) {
                let #(_, variable) = pair
                variable
              },
            )
          try typer = unify(type_, Data(type_name, type_params), typer)
          case list.zip(replaced_arguments, assignments) {
            Ok(zipped) -> {
              let scope = do_push_arguments(zipped, scope)
              Ok(#(scope, typer))
            }
            Error(#(expected, given)) ->
              Error(IncorrectArity(expected: expected, given: given))
          }
        }
      }
  }
}

fn generate_replacement_vars(
  parameterised,
  replacements,
  typer,
) -> #(List(#(Int, Type)), Typer) {
  case parameterised {
    [] -> #(list.reverse(replacements), typer)
    [i, ..parameterised] -> {
      let #(var, typer) = generate_type_var(typer)
      generate_replacement_vars(
        parameterised,
        [#(i, var), ..replacements],
        typer,
      )
    }
  }
}

fn replace_variables(arguments, replacements, acc) {
  case arguments {
    [] -> list.reverse(acc)
    [Variable(p), ..arguments] -> {
      let Ok(new_var) = list.key_find(replacements, p)
      replace_variables(arguments, replacements, [new_var, ..acc])
    }
    [Data(name, inner), ..arguments] ->
      replace_variables(
        arguments,
        replacements,
        [Data(name, replace_variables(inner, replacements, [])), ..acc],
      )
  }
}

fn do_match_remaining_clauses(rest, state) {
  let #(subject_type, first_type, typed_clauses, environment, typer) = state
  case rest {
    [] -> Ok(#(list.reverse(typed_clauses), typer))
    [clause, ..rest] -> {
      let #(pattern, then) = clause
      try #(inner_env, typer) =
        bind_pattern(pattern, subject_type, environment, typer)
      try #(type_, tree, typer) = do_infer(then, inner_env, typer)
      try typer = unify(type_, first_type, typer)
      do_match_remaining_clauses(
        rest,
        #(
          subject_type,
          first_type,
          [#(pattern, #(type_, tree)), ..typed_clauses],
          environment,
          typer,
        ),
      )
    }
  }
}

fn do_infer(untyped, scope, typer) {
  let #(Nil, expression) = untyped
  case expression {
    Binary -> Ok(#(Data("Binary", []), Binary, typer))
    Let(pattern, value, in: next) -> {
      try #(value_type, value_tree, typer) = do_infer(value, scope, typer)
      try #(scope, typer) = bind_pattern(pattern, value_type, scope, typer)
      try #(next_type, next_tree, typer) = do_infer(next, scope, typer)
      let tree =
        Let(pattern, #(value_type, value_tree), #(next_type, next_tree))
      Ok(#(next_type, tree, typer))
    }
    Var(name) -> {
      try poly_type = scope.get_variable(scope, name)
      let #(var_type, typer) = instantiate(poly_type, typer)
      Ok(#(var_type, Var(name), typer))
    }
    Case(subject, clauses) ->
      case clauses {
        [first, second, ..rest] -> {
          let rest = [second, ..rest]
          try #(subject_type, subject_tree, typer) =
            do_infer(subject, scope, typer)
          let #(first_pattern, first_then) = first
          try #(first_env, typer) =
            bind_pattern(first_pattern, subject_type, scope, typer)
          try #(first_type, first_tree, typer) =
            do_infer(first_then, first_env, typer)
          try #(clauses, typer) =
            do_match_remaining_clauses(
              rest,
              #(subject_type, first_type, [], scope, typer),
            )
          let tree =
            Case(
              #(subject_type, subject_tree),
              [#(first_pattern, #(first_type, first_tree)), ..clauses],
            )
          Ok(#(first_type, tree, typer))
        }
        _ -> todo("Must be at least two clauses")
      }
    Fn(with, in) -> {
      let #(typed_with, scope, typer) = push_arguments(with, scope, typer)
      let arguments = do_typed_arguments_remove_name(typed_with, [])
      let #(return_type, typer) = generate_type_var(typer)
      let type_ = Function(arguments, return_type)
      let scope = do_push_arguments([#(type_, "self")], scope)
      try #(in_type, in_tree, typer) = do_infer(in, scope, typer)
      try typer = unify(return_type, in_type, typer)
      let tree = Fn(typed_with, #(in_type, in_tree))
      Ok(#(type_, tree, typer))
    }
    Call(function, with) -> {
      try #(f_type, f_tree, typer) = do_infer(function, scope, typer)
      try #(with, typer) = do_infer_call_args(with, scope, typer, [])
      let #(return_type, typer) = generate_type_var(typer)
      // expected function found blah
      // io.debug(expected found)
      // Pass situation to unification. caseclause function call argument/variable
      // I think we can leave the situation in the AST module, types maybe just need some metadata on the position
      // Big things, better errors and eval functionality.
      try typer =
        unify(
          f_type,
          Function(
            list.map(with, fn(x: #(Type, Expression(Type))) { x.0 }),
            return_type,
          ),
          typer,
        )
      let type_ = return_type
      let tree = Call(#(f_type, f_tree), with)
      Ok(#(type_, tree, typer))
    }
  }
}

// TODO extract and test generalize and instantiate
// Test not poly when equals string
// occurs in
fn do_infer_call_args(arguments, environment, typer, accumulator) {
  case arguments {
    [] -> Ok(#(list.reverse(accumulator), typer))
    [untyped, ..rest] -> {
      try #(type_, tree, typer) = do_infer(untyped, environment, typer)
      do_infer_call_args(
        rest,
        environment,
        typer,
        [#(type_, tree), ..accumulator],
      )
    }
  }
}
