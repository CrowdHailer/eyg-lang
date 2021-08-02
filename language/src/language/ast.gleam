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

pub fn infer(untyped, environment) {
  do_infer(untyped, environment, type_.checker())
}

fn generalise(type_, scope, typer) {
  let type_ = type_.resolve_type(type_, typer)
  let excluded = scope.free_variables(scope)
  PolyType(type_.generalised_by(type_, excluded, typer), type_)
}

fn set_variable(scope, label, type_, typer) {
  generalise(type_, scope, typer)
  |> scope.set_variable(scope, label, _)
}

fn set_arguments(scope, arguments, typer) {
  list.fold(
    arguments,
    scope,
    fn(item, scope) {
      let #(type_, name) = item
      set_variable(scope, name, type_, typer)
    },
  )
}

// let a = foo
// a is expected to match the type of foo becuase foo gets calculate first
// works well in cases where previous pattern specifies type of destructure.
fn bind(pattern, expected, scope, typer) {
  case pattern {
    Assignment(name) -> {
      let scope = set_variable(scope, name, expected, typer)
      Ok(#(scope, typer))
    }
    Destructure(constructor, with) -> {
      try #(type_name, parameters, arguments) =
        scope.get_constructor(scope, constructor)
      let #(replacements, typer) =
        generate_replacement_vars(parameters, [], typer)
      let replaced_arguments = replace_variables(arguments, replacements, [])
      let type_params =
        list.map(
          replacements,
          fn(pair) {
            let #(_, variable) = pair
            variable
          },
        )
      try typer = unify(Data(type_name, type_params), expected, typer)
      case list.zip(replaced_arguments, with) {
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

// This can probably get moved to scope somewhere
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

fn type_arguments(arguments, typer) {
  do_type_arguments(arguments, [], typer)
}

fn do_type_arguments(arguments, accumulator, typer) {
  case arguments {
    [] -> #(list.reverse(accumulator), typer)
    [#(Nil, name), ..arguments] -> {
      let #(type_, typer) = generate_type_var(typer)
      do_type_arguments(arguments, [#(type_, name), ..accumulator], typer)
    }
  }
}

fn infer_arguments(arguments, scope, typer) {
  do_infer_arguments(arguments, [], scope, typer)
}

fn do_infer_arguments(arguments, accumulator, scope, typer) {
  case arguments {
    [] -> Ok(#(list.reverse(accumulator), typer))
    [argument, ..arguments] -> {
      try #(type_, tree, typer) = do_infer(argument, scope, typer)
      let accumulator = [#(type_, tree), ..accumulator]
      do_infer_arguments(arguments, accumulator, scope, typer)
    }
  }
}

fn do_infer(untyped, scope, typer) {
  let #(Nil, expression) = untyped
  case expression {
    Binary -> Ok(#(Data("Binary", []), Binary, typer))
    Let(pattern, value, in: next) -> {
      try #(value_type, value_tree, typer) = do_infer(value, scope, typer)
      try #(scope, typer) = bind(pattern, value_type, scope, typer)
      try #(next_type, next_tree, typer) = do_infer(next, scope, typer)
      let tree =
        Let(pattern, #(value_type, value_tree), #(next_type, next_tree))
      Ok(#(next_type, tree, typer))
    }
    Var(name) -> {
      try poly_type = scope.get_variable(scope, name)
      let #(var_type, typer) = type_.instantiate(poly_type, typer)
      Ok(#(var_type, Var(name), typer))
    }
    Case(subject, clauses) -> {
      case clauses {
        [_first, _second, ..rest] -> Ok(Nil)
        _ -> todo("Must be at least two clauses")
      }
      try #(subject_type, subject_tree, typer) = do_infer(subject, scope, typer)
      let subject = #(subject_type, subject_tree)
      let #(return_type, typer) = generate_type_var(typer)
      try #(accumulator, typer) =
        list.try_fold(
          clauses,
          #([], typer),
          fn(clause, state) {
            let #(accumulator, typer) = state
            let #(pattern, then) = clause
            try #(scope, typer) = bind(pattern, subject_type, scope, typer)
            try #(type_, tree, typer) = do_infer(then, scope, typer)
            try typer = unify(type_, return_type, typer)
            let clause = #(pattern, #(type_, tree))
            let accumulator = [clause, ..accumulator]
            Ok(#(accumulator, typer))
          },
        )
      let clauses = list.reverse(accumulator)
      let tree = Case(subject, clauses)
      Ok(#(return_type, tree, typer))
    }
    Fn(for, in) -> {
      let #(for, typer) = type_arguments(for, typer)
      let scope = set_arguments(scope, for, typer)
      let #(return_type, typer) = generate_type_var(typer)
      let argument_types = list.map(for, fn(a: #(Type, String)) { a.0 })
      let type_ = Function(argument_types, return_type)
      let scope = set_variable(scope, "self", type_, typer)
      try #(in_type, in_tree, typer) = do_infer(in, scope, typer)
      try typer = unify(return_type, in_type, typer)
      let tree = Fn(for, #(in_type, in_tree))
      Ok(#(type_, tree, typer))
    }
    Call(function, with) -> {
      try #(f_type, f_tree, typer) = do_infer(function, scope, typer)
      try #(with, typer) = infer_arguments(with, scope, typer)
      let #(return_type, typer) = generate_type_var(typer)
      // because given 3 args
      let given =
        Function(
          list.map(with, fn(x: #(Type, Expression(Type))) { x.0 }),
          return_type,
        )
      try typer = unify(given, f_type, typer)
      let type_ = return_type
      let tree = Call(#(f_type, f_tree), with)
      Ok(#(type_, tree, typer))
    }
  }
}
