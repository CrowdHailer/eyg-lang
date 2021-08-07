import gleam/io
import gleam/list
import gleam/option.{None, Some}
import language/scope
import language/type_.{
  Data, Function, IncorrectArity, PolyType, RedundantClause, Type, UnhandledVarients,
  Variable, generate_type_var,
}

/// Type destructure used for let and case statements
pub type Pattern(l) {
  Destructure(String, List(l))
  TuplePattern(List(l))
  RowPattern(List(#(String, l)))
  Assignment(l)
}

// data("boolean::Boolean", [], [
//   constructor("True", [])
//   constructor("False", [])
// ])
// data("option::Result", [1], [
//   constructor("Ok", [variable(1)])
//   constructor("Error", [])
// ])
// data2("result::Result", fn(success, error) {
//   constructor("Ok", [Data("string::String", []), success])
// }, )
/// Expression tree with type information
pub type Expression(t, l) {
  NewData(
    name: String,
    parameters: List(Int),
    constructors: List(#(l, List(Type))),
    in: #(t, Expression(t, l)),
  )
  Let(
    pattern: Pattern(l),
    value: #(t, Expression(t, l)),
    in: #(t, Expression(t, l)),
  )
  Var(label: l)
  Binary(content: String)
  Tuple(values: List(#(t, Expression(t, l))))
  Row(rows: List(#(String, #(t, Expression(t, l)))))
  Case(
    subject: #(t, Expression(t, l)),
    clauses: List(#(Pattern(l), #(t, Expression(t, l)))),
  )
  // Clashes with Function Type, maybe call Anonymous, Lambda
  Fn(arguments: List(#(t, l)), body: #(t, Expression(t, l)))
  Call(
    function: #(t, Expression(t, l)),
    arguments: List(#(t, Expression(t, l))),
  )
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
  let #(scope, reversed) =
    list.fold(
      arguments,
      #(scope, []),
      fn(item, state) {
        let #(scope, accumulator) = state
        let #(type_, name) = item
        let #(scope, quantified_label) = set_variable(scope, name, type_, typer)
        #(scope, [#(type_, quantified_label), ..accumulator])
      },
    )
  #(scope, list.reverse(reversed))
}

pub type Handles {
  All
  Single(String)
}

// TODO this makes  invalid erl somehow
// fn test(x) {
//   [..x]
// }
fn bind(pattern, expected, scope, typer) {
  case pattern {
    Assignment(label) -> {
      let #(scope, quantified_label) =
        set_variable(scope, label, expected, typer)
      let pattern = Assignment(quantified_label)
      Ok(#(pattern, All, scope, typer))
    }
    TuplePattern(with) -> {
      let situation = ValueDestructuring("Tuple")
      let #(typer, reversed) =
        list.fold(
          with,
          #(typer, []),
          fn(label, state) {
            let #(typer, accumulator) = state
            let #(tvar, typer) = generate_type_var(typer)
            let accumulator = [#(label, tvar), ..accumulator]
            #(typer, accumulator)
          },
        )
      let #(scope, with) =
        list.fold(
          reversed,
          #(scope, []),
          fn(item, state) {
            let #(scope, accumulator) = state
            let #(label, type_) = item
            let #(scope, label) = set_variable(scope, label, type_, typer)
            let accumulator = [#(label, type_), ..accumulator]
            #(scope, accumulator)
          },
        )
      let type_ =
        Data("Tuple", list.map(with, fn(x: #(#(String, Int), Type)) { x.1 }))
      try typer = unify(type_, expected, typer, situation)
      let assignments = list.map(with, fn(x: #(#(String, Int), Type)) { x.0 })
      Ok(#(TuplePattern(assignments), All, scope, typer))
    }
    RowPattern(rows) -> {
      let situation = ValueDestructuring("Row")
      let #(typer, reversed) =
        list.fold(
          rows,
          #(typer, []),
          fn(item, state) {
            let #(typer, accumulator) = state
            let #(row_name, label) = item
            let #(tvar, typer) = generate_type_var(typer)
            let accumulator = [#(label, #(row_name, tvar)), ..accumulator]
            #(typer, accumulator)
          },
        )
      let #(scope, row) =
        list.fold(
          reversed,
          #(scope, []),
          fn(item, state) {
            let #(scope, accumulator) = state
            let #(label, #(row_name, type_)) = item
            let #(scope, label) = set_variable(scope, label, type_, typer)
            let accumulator = [
              #(#(row_name, label), #(row_name, type_)),
              ..accumulator
            ]
            #(scope, accumulator)
          },
        )
      let #(remaining_row, typer) = generate_type_var(typer)
      let type_ =
        type_.Row(
          list.map(
            row,
            fn(x: #(#(String, #(String, Int)), #(String, Type))) { x.1 },
          ),
          Some(remaining_row),
        )
      try typer = unify(type_, expected, typer, situation)
      let assignments =
        list.map(
          row,
          fn(x: #(#(String, #(String, Int)), #(String, Type))) { x.0 },
        )
      Ok(#(RowPattern(assignments), All, scope, typer))
    }
    Destructure(constructor, with) -> {
      let situation = ValueDestructuring(constructor)
      // TODO this needs to be getting a proper constructor
      // Fix euqal to 1 to ensure constructor not overwritten
      try #(poly_type, 1) =
        scope.get_variable(scope, constructor)
        |> with_situation(VarLookup)
      let #(type_, typer) = type_.instantiate(poly_type, typer)
      // TODO a get constructor should work here see notes in type
      let Function(arguments, return) = type_
      try typer = unify(return, expected, typer, situation)
      try #(scope, with) =
        case list.zip(arguments, with) {
          Ok(zipped) -> Ok(set_arguments(scope, zipped, typer))
          Error(#(expected, given)) ->
            Error(IncorrectArity(expected: expected, given: given))
        }
        |> with_situation(situation)
      // maybe the destructure should take types
      let with =
        list.map(
          with,
          fn(typed) {
            let #(_, quantified_label) = typed
            quantified_label
          },
        )
      Ok(#(Destructure(constructor, with), Single(constructor), scope, typer))
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

fn add_constructors(scope, constructors, type_name, params, accumulator) {
  case constructors {
    [] -> #(scope, list.reverse(accumulator))
    [#(label, arguments), ..rest] -> {
      let new_type = Data(type_name, list.map(params, Variable))
      let poly_type =
        PolyType(forall: params, type_: Function(arguments, new_type))
      let #(scope, label) = scope.set_variable(scope, label, poly_type)
      add_constructors(
        scope,
        rest,
        type_name,
        params,
        [#(label, arguments), ..accumulator],
      )
    }
  }
}

fn do_infer(untyped, scope, typer) {
  let #(Nil, expression) = untyped
  case expression {
    NewData(type_name, parameters, constructors, in) -> {
      let #(scope, arguments) =
        add_constructors(scope, constructors, type_name, parameters, [])
      let Ok(typer) =
        type_.register_type(
          typer,
          type_name,
          list.map(
            constructors,
            fn(constructor) {
              let #(name, _) = constructor
              name
            },
          ),
        )
      try #(in_type, in_tree, typer) = do_infer(in, scope, typer)
      let tree = NewData(type_name, parameters, arguments, #(in_type, in_tree))
      Ok(#(in_type, tree, typer))
    }
    Binary(content) -> Ok(#(Data("Binary", []), Binary(content), typer))
    // rename to elemeents to elements vs rows have values
    Tuple(values) -> {
      try #(reversed, typer) =
        list.try_fold(
          values,
          #([], typer),
          fn(value, state) {
            let #(accumulator, typer) = state
            try #(value_type, value_tree, typer) = do_infer(value, scope, typer)
            let accumulator = [#(value_type, value_tree), ..accumulator]
            Ok(#(accumulator, typer))
          },
        )
      let subexpressions = list.reverse(reversed)
      let value_types =
        list.map(
          subexpressions,
          fn(s) {
            let #(type_, _) = s
            type_
          },
        )
      Ok(#(Data("Tuple", value_types), Tuple(subexpressions), typer))
    }
    Row(rows) -> {
      try #(reversed, typer) =
        list.try_fold(
          rows,
          #([], typer),
          fn(row, state) {
            let #(accumulator, typer) = state
            let #(name, value) = row
            try #(value_type, value_tree, typer) = do_infer(value, scope, typer)
            let accumulator = [
              #(name, #(value_type, value_tree)),
              ..accumulator
            ]
            Ok(#(accumulator, typer))
          },
        )
      let subexpressions = list.reverse(reversed)
      let row_types =
        list.map(
          subexpressions,
          fn(s) {
            let #(name, #(type_, _)) = s
            #(name, type_)
          },
        )
      Ok(#(type_.Row(row_types, None), Row(subexpressions), typer))
    }
    Let(pattern, value, in: next) -> {
      try #(value_type, value_tree, typer) = do_infer(value, scope, typer)
      try #(pattern, handles, scope, typer) =
        bind(pattern, value_type, scope, typer)
      try _ = case handles {
        All -> Ok(Nil)
        Single(constructor) -> {
          let Data(type_name, _params) = type_.resolve_type(value_type, typer)
          let Ok(varients) = type_.get_varients(typer, type_name)
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
      try #(poly_type, count) =
        scope.get_variable(scope, name)
        |> with_situation(VarLookup)
      let #(var_type, typer) = type_.instantiate(poly_type, typer)
      Ok(#(var_type, Var(#(name, count)), typer))
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
            try #(pattern, handles, scope, typer) =
              bind(pattern, subject_type, scope, typer)
            try #(type_, tree, typer) = do_infer(then, scope, typer)
            try typer = unify(type_, return_type, typer, CaseClause)
            let remaining = case remaining {
              Error(Nil) -> {
                let Data(type_name, _params) =
                  type_.resolve_type(subject_type, typer)
                let Ok(varients) = type_.get_varients(typer, type_name)
                varients
              }
              Ok(remaining) -> remaining
            }
            try remaining = case remaining, handles {
              [], All -> Error(#(RedundantClause("_"), CaseClause))
              _, All -> Ok([])
              remaining, Single(varient) ->
                case list.pop(remaining, varient) {
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
      let #(scope, quantified_for) = set_arguments(scope, for, typer)
      let #(return_type, typer) = generate_type_var(typer)
      let argument_types = list.map(for, fn(a: #(Type, String)) { a.0 })
      let type_ = Function(argument_types, return_type)
      // TODO tail optimise recursive functions
      let #(scope, _todo_number) = set_variable(scope, "self", type_, typer)
      try #(in_type, in_tree, typer) = do_infer(in, scope, typer)
      try typer = unify(return_type, in_type, typer, ReturnAnnotation)
      let tree = Fn(quantified_for, #(in_type, in_tree))
      Ok(#(type_, tree, typer))
    }
    Call(function, with) -> {
      try #(f_type, f_tree, typer) = do_infer(function, scope, typer)
      try #(with, typer) = infer_arguments(with, scope, typer)
      let #(return_type, typer) = generate_type_var(typer)
      // because given 3 args
      let given =
        Function(
          list.map(
            with,
            fn(x: #(Type, Expression(Type, #(String, Int)))) { x.0 },
          ),
          return_type,
        )
      try typer = unify(given, f_type, typer, FunctionCall)
      let type_ = return_type
      let tree = Call(#(f_type, f_tree), with)
      Ok(#(type_, tree, typer))
    }
  }
}
