import gleam/io
import gleam/list
import language/scope
import language/type_.{
  Data, Function, IncorrectArity, PolyType, Type, UnhandledVarients, RedundantClause,
  generate_type_var,
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

pub type UnifySituation {
  // let a = foo
  // a is expected to match the type of foo becuase foo gets calculate first
  // works well in cases where previous pattern specifies type of destructure.
  ValueDestructuring(constructor: String)
  CaseClause
  // Never happens without annotation
  ReturnAnnotation
  FunctionCall
  // Not a unify situation unless env is row type 
  VarLookup
}

fn unify(given, expected, typer, situation) {
  type_.unify(given, expected, typer)
  |> with_situation(situation)
}

// NEEDS ANNOTATION
fn with_situation(
  result: Result(a, b),
  situation: UnifySituation,
) -> Result(a, #(b, UnifySituation)) {
  case result {
    Ok(typer) -> Ok(typer)
    Error(failure) -> Error(#(failure, situation))
  }
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

pub type Handles {
  All
  Single(String)
}

fn bind(pattern, expected, scope, typer) {
  case pattern {
    Assignment(name) -> {
      let scope = set_variable(scope, name, expected, typer)
      Ok(#(All, scope, typer))
    }
    Destructure(constructor, with) -> {
      let situation = ValueDestructuring(constructor)
      try poly_type =
        scope.get_variable(scope, constructor)
        |> with_situation(VarLookup)
      let #(type_, typer) = type_.instantiate(poly_type, typer)
      // TODO a get constructor should work here see notes in type
      let Function(arguments, return) = type_
      try typer = unify(return, expected, typer, situation)
      try scope =
        case list.zip(arguments, with) {
          Ok(zipped) -> Ok(set_arguments(scope, zipped, typer))
          Error(#(expected, given)) ->
            Error(IncorrectArity(expected: expected, given: given))
        }
        |> with_situation(situation)
      Ok(#(Single(constructor), scope, typer))
    }
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
      try #(handles, scope, typer) = bind(pattern, value_type, scope, typer)
      try _ = case handles {
        All -> Ok(Nil)
        Single(constructor) -> {
          let Data(type_name, _params) = type_.resolve_type(value_type, typer)
          let varients = scope.get_varients(scope, type_name)
          assert Ok(remaining) = list.pop(varients, constructor)
          case remaining {
            [] -> Ok(Nil)
            _ ->
              Error(#(
                UnhandledVarients(remaining),
                ValueDestructuring(constructor),
              ))
          }
        }
      }
      try #(next_type, next_tree, typer) = do_infer(next, scope, typer)
      let tree =
        Let(pattern, #(value_type, value_tree), #(next_type, next_tree))
      Ok(#(next_type, tree, typer))
    }
    Var(name) -> {
      try poly_type =
        scope.get_variable(scope, name)
        |> with_situation(VarLookup)
      let #(var_type, typer) = type_.instantiate(poly_type, typer)
      Ok(#(var_type, Var(name), typer))
    }
    Case(subject, clauses) -> {
      case clauses {
        [_first, _second, .._rest] -> Nil
        // Fist can't be an assignment otherwise the type doesn't get infered to a datatype
        _ -> todo("Must be at least two clauses")
      }
      try #(subject_type, subject_tree, typer) = do_infer(subject, scope, typer)
      let subject = #(subject_type, subject_tree)
      let #(return_type, typer) = generate_type_var(typer)
      try #(accumulator, typer, Ok(remaining)) =
        list.try_fold(
          clauses,
          // Uses Error(Nil) for not yet looked up remaining
           #([], typer, Error(Nil)),
          fn(clause, state) {
            let #(accumulator, typer, remaining) = state
            let #(pattern, then) = clause
            try #(handles, scope, typer) = bind(pattern, subject_type, scope, typer)

            try #(type_, tree, typer) = do_infer(then, scope, typer)
            try typer = unify(type_, return_type, typer, CaseClause)

            let remaining = case remaining {
              Error(Nil) -> {
                let Data(type_name, _params) = type_.resolve_type(subject_type, typer)
                scope.get_varients(scope, type_name)
              }
              Ok(remaining) -> remaining
            }

            try remaining = case remaining, handles {
              [], All -> Error(#(RedundantClause("_"), CaseClause))
              _, All -> Ok([])
              remaining, Single(varient) -> case list.pop(remaining, varient) {
                Ok(remaining) -> Ok(remaining)
                Error(Nil) -> Error(#(RedundantClause(varient), CaseClause))
              }
            }
                        
            // counting handled doesnt track the case True | False | variable
            // state would switch from [True,  False] to All
            // Would need to track state as List(Constructors) + Rest

            let clause = #(pattern, #(type_, tree))
            let accumulator = [clause, ..accumulator]
            Ok(#(accumulator, typer, Ok(remaining)))
          },
        )
      try _ = case remaining {
        [] -> Ok(Nil)
        remaining -> Error(#(UnhandledVarients(remaining), CaseClause))
      }
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
      try typer = unify(return_type, in_type, typer, ReturnAnnotation)
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
      try typer = unify(given, f_type, typer, FunctionCall)
      let type_ = return_type
      let tree = Call(#(f_type, f_tree), with)
      Ok(#(type_, tree, typer))
    }
  }
}
