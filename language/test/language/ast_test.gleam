import language/ast.{Binary, Call, Expression, Function, Var, Tuple}
import io


pub type Type {
  Constructor(String, List(Type))
  Variable(Int)
}

// type checker state
type State {
  State(
    // tracking names to types
      environment: List(#(String, Type)), 
      substitutions: List(Type),
      type_variable_counter: Int
      )
}

fn find_in_env(state, name) {
  let State(environment, ..) = state
  do_find_in_env(environment, name)
}

fn do_find_in_env(environment, name) {
  case environment {
    [] -> Error(Nil)
    [#(key, given), .._] if key == name -> Ok(given)
    [_, ..rest] -> do_find_in_env(rest, name)
  }
}

fn push_arguments(
  arguments,
  typed: List(#(Type, String)),
  state,
) -> #(List(#(Type, String)), State) {
  case arguments {
    [] -> #(typed, state)
    [#(Nil, name), ..rest] -> {
      let State(environment, substitutions, type_variable_counter) = state
      let type_variable_counter = type_variable_counter + 1
      let type_variable = Variable(type_variable_counter)
      let environment = [#(name, type_variable), ..environment]
      let typed = [#(type_variable, name), ..typed]
      let state = State(environment, substitutions, type_variable_counter)
      push_arguments(rest, typed, state)
    }
  }
}

fn reverse(remaining, accumulator) {
  case remaining {
    [] -> accumulator
    [next, ..rest] -> reverse(rest, [next, ..accumulator])
  }
}

fn unify_function_arguments(for, with, state) {
    let State(substitutions: substitutions, ..) = state
  case for, with {
    [return_type], [] -> Ok(#(return_type, substitutions))
    [t1, ..for], [tree, ..with] -> {
      try #(t2, _expression, _sub) = infer(tree, state)
      io.debug(t1)
      io.debug(t2)
      try substitutions = unify(t1, t2)
      let state = State(..state, substitutions: substitutions)
      unify_function_arguments(for, with, state)
    }
  }
}

// Just bind and see what happens
fn unify(t1, t2) {
    case t1, t2 {
        Variable(i), Constructor(_, _) ->  Ok([t2])
    }
}

fn typed_arguments_remove_name(remaining, accumulator) {
  case remaining {
    [] -> accumulator
    [#(typed, _name), ..rest] ->
      typed_arguments_remove_name(rest, [typed, ..accumulator])
  }
}

fn infer(tree, state) -> Result(#(Type, Expression(Type), List(Type)), Nil) {
  let #(Nil, expression) = tree
  case expression {
    Binary -> Ok(#(Constructor("Binary", []), Binary, []))
    Function(arguments, body) -> {
      let #(typed_arguments, state) = push_arguments(arguments, [], state)
      try #(return_type, tree, _) = infer(body, state)
      let body = #(return_type, tree)
      let constructor_arguments: List(Type) =
        typed_arguments_remove_name(typed_arguments, [return_type])
      Ok(#(
        Constructor("Function", constructor_arguments),
        Function(typed_arguments, body), [],
      ))
    }
    // Call(with) Function(for)
    Call(function, with) -> {
      try #(function_type, _, _) = infer(function, state)
      case function_type {
        Constructor("Function", for) -> {
            // return substitutions
          try #(return_type, substitutions) = unify_function_arguments(for, with, state)
          Ok(#(return_type, Tuple, substitutions))
        }
      }
    }
    // Ok(return_type)
    Var(name) -> {
      try var_type = find_in_env(state, name)
      Ok(#(var_type, Var(name), []))
    }
  }
}

pub fn infer_call_test() {
  let initial = State([], [], 0)
  let ast = #(Nil, Call(#(Nil, Function([], #(Nil, Binary))), []))
  let Ok(#(Constructor("Binary", []), _, _)) = infer(ast, initial)
}

pub fn infer_call_with_arguments_test() {
  let initial = State([], [], 0)
  let ast = #(
    Nil,
    Call(#(Nil, Function([#(Nil, "x")], #(Nil, Var("x")))), [#(Nil, Binary)]),
  )
  let Ok(#(Constructor("Binary", []), _, _)) = infer(ast, initial)
}
