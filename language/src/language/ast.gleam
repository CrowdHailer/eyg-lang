import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import language/scope
import language/type_.{
  Constructor, PolyType, Type, Typer, Variable, generate_type_var, unify,
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
  Function(arguments: List(#(t, String)), body: #(t, Expression(t)))
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

fn typer() {
  Typer([], 10)
}

pub fn infer(untyped, environment) {
  let typer = typer()
  try #(type_, tree, typer) = do_infer(untyped, environment, typer)
  let Typer(substitutions: substitutions, ..) = typer
  Ok(#(type_, tree, substitutions))
}

//       TODO remove free variables that all already in the environment as they might get bound later
// Can I convince myself that all generalisable variables must be above the typer current counter
// Yes because the environment is passed in and not used again.
// call this fn generalise when called here.
fn free_type_vars_in_type(type_) {
  case type_ {
    Constructor("Function", [Variable(x), Variable(y)]) if x == y -> [y]
    _ -> []
  }
}

fn instantiate(poly_type, typer) {
  let PolyType(forall, type_) = poly_type
  do_instantiate(forall, type_, typer)
}

fn do_instantiate(forall, type_, typer) {
  case forall {
    [] -> #(type_, typer)
    [i, ..rest] -> {
      let #(type_var, typer) = generate_type_var(typer)
      let Constructor(name, arguments) = type_
      let arguments = do_replace_variables(arguments, Variable(i), type_var, [])
      let type_ = Constructor(name, arguments)
      do_instantiate(rest, type_, typer)
    }
  }
}

fn do_replace_variables(arguments, old, new, accumulator) {
  case arguments {
    [] -> list.reverse(accumulator)
    [argument, ..rest] -> {
      let replacement = case argument == old {
        True -> new
        False -> argument
      }
      do_replace_variables(rest, old, new, [replacement, ..accumulator])
    }
  }
}

fn bind_pattern(pattern, type_, scope, typer) {
  case pattern {
    Assignment(name) -> {
      let forall = free_type_vars_in_type(type_)
      let scope = scope.set_variable(scope, name, PolyType(forall, type_))
      Ok(#(scope, typer))
    }
    Destructure(constructor, with) ->
      case constructor, with {
        "Function", _ -> todo("Can;t destructure function")
        constructor, assignments -> {
          try #(type_name, parameters, arguments) =
            scope.get_constructor(scope, constructor)
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
          try typer = unify(type_, Constructor(type_name, type_params), typer)
          let Ok(zipped) = list.zip(replaced_arguments, assignments)
          let scope = do_push_arguments(zipped, scope)
          Ok(#(scope, typer))
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
    [Constructor(name, inner), ..arguments] ->
      replace_variables(
        arguments,
        replacements,
        [Constructor(name, replace_variables(inner, replacements, [])), ..acc],
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
    Binary -> Ok(#(Constructor("Binary", []), Binary, typer))
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

    // can do silly things like define a function in case subject and use in clause.
    // This would need generalising
    // TODO recursion
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
    Function(with, in) -> {
      // There's no lets in arguments that escape the scope so keep reusing initial scope
      let #(typed_with, scope, typer) = push_arguments(with, scope, typer)
      // Only use unkown return type when in recursive fn. should always be unified with something otherwise void.
      // try unifying with never
      let #(unknown_return_type, typer) = generate_type_var(typer)
      let constructor_arguments =
        do_typed_arguments_remove_name(typed_with, [])
        |> list.append([unknown_return_type])
      let recur_type = Constructor("Function", constructor_arguments)
      let scope = do_push_arguments([#(recur_type, "self")], scope)
      try #(in_type, in_tree, typer) = do_infer(in, scope, typer)
      let constructor_arguments =
        do_typed_arguments_remove_name(typed_with, [])
        |> list.append([in_type])
      try typer = unify(unknown_return_type, in_type, typer)
      let type_ = Constructor("Function", constructor_arguments)
      let tree = Function(typed_with, #(in_type, in_tree))
      Ok(#(type_, tree, typer))
    }
    // N eed to understand generics but could every typed ast have a variable
    Call(function, with) -> {
      try #(f_type, f_tree, typer) = do_infer(function, scope, typer)
      try #(with_typed, typer) = do_infer_call_args(with, scope, typer, [])
      // Think generating the return type is needed for handling recursive.
      let #(return_type, typer) = generate_type_var(typer)
      try typer =
        unify(
          f_type,
          Constructor("Function", append_only_the_type(with_typed, return_type)),
          typer,
        )
      let type_ = return_type
      let tree = Call(#(f_type, f_tree), with_typed)
      Ok(#(type_, tree, typer))
    }
  }
}

pub fn append_only_the_type(before, new) {
  do_append_only_the_type(list.reverse(before), [new])
}

fn do_append_only_the_type(remaining, accumulator) {
  case remaining {
    [] -> accumulator
    [#(type_, tree), ..rest] ->
      do_append_only_the_type(rest, [type_, ..accumulator])
  }
}

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
