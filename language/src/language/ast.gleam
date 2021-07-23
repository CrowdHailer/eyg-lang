import gleam/list
import gleam/option.{None, Option, Some}

// Use opaque type to keep in type information
pub type Expression(t) {
  // Pattern is name in Let
  Let(name: String, value: #(t, Expression(t)), in: #(t, Expression(t)))
  Var(name: String)
  Binary
  Case
  Tuple
  // arguments are names only
  Function(arguments: List(#(t, String)), body: #(t, Expression(t)))
  Call(function: #(t, Expression(t)), arguments: List(#(t, Expression(t))))
}

pub fn let_(name, value, in) {
  #(Nil, Let(name, value, in))
}

pub fn var(name) {
  #(Nil, Var(name))
}

pub fn binary() {
  #(Nil, Binary)
}

pub fn function(for, in) {
  #(Nil, Function(for, in))
}

pub fn call(function, with) {
  #(Nil, Call(function, with))
}

// Typed
pub type Type {
  Constructor(String, List(Type))
  Variable(Int)
}

// A linear type on substitutions would ensure passed around
// TODO merge substitutions, need to keep passing next var in typer
// type checker state
type Typer {
  Typer(// tracking names to types
    // environment: List(#(String, Type)),
    // typer passed as globally acumulating set, env is scoped
    substitutions: List(#(Int, Type)), next_type_var: Int)
}

fn typer() {
  Typer([], 1)
}

fn push_variable(environment, name, type_) {
  [#(name, type_), ..environment]
}

fn fetch_variable(environment, name) {
  case list.key_find(environment, name) {
    Ok(value) -> Ok(value)
    Error(Nil) -> Error("Variable not in environment")
  }
}

// fn find_in_env(state, name) {
//   let State(environment, ..) = state
//   do_find_in_env(environment, name)
// }
// fn do_find_in_env(environment, name) {
//   case environment {
//     [] -> Error(Nil)
//     [#(key, given), .._] if key == name -> Ok(given)
//     [_, ..rest] -> do_find_in_env(rest, name)
//   }
// }
// fn push_arguments(
//   arguments,
//   typed: List(#(Type, String)),
//   state,
// ) -> #(List(#(Type, String)), State) {
//   case arguments {
//     [] -> #(typed, state)
//     [#(Nil, name), ..rest] -> {
//       let State(environment, substitutions, type_variable_counter) = state
//       let type_variable_counter = type_variable_counter + 1
//       let type_variable = Variable(type_variable_counter)
//       let environment = [#(name, type_variable), ..environment]
//       let typed = [#(type_variable, name), ..typed]
//       let state = State(environment, substitutions, type_variable_counter)
//       push_arguments(rest, typed, state)
//     }
//   }
// }
// fn unify_function_arguments(for, with, state) {
//     let State(substitutions: substitutions, ..) = state
//   case for, with {
//     [return_type], [] -> Ok(#(return_type, substitutions))
//     [t1, ..for], [tree, ..with] -> {
//       try #(t2, _expression, _sub) = infer(tree, state)
//       io.debug(t1)
//       io.debug(t2)
//       try substitutions = unify(t1, t2)
//       let state = State(..state, substitutions: substitutions)
//       unify_function_arguments(for, with, state)
//     }
//   }
// }
// // Just bind and see what happens
// fn unify(t1, t2) {
//     case t1, t2 {
//         Variable(i), Constructor(_, _) ->  Ok([t2])
//     }
// }
// fn typed_arguments_remove_name(remaining, accumulator) {
//   case remaining {
//     [] -> accumulator
//     [#(typed, _name), ..rest] ->
//       typed_arguments_remove_name(rest, [typed, ..accumulator])
//   }
// }
pub fn infer(untyped) {
  try #(type_, tree, typer) = do_infer(untyped, [], typer())
  let Typer(substitutions: substitutions, ..) = typer
  Ok(#(type_, tree, substitutions))
}

fn do_infer(untyped, environment, typer) {
  let #(Nil, expression) = untyped
  case expression {
    Binary -> Ok(#(Constructor("Binary", []), Binary, typer))
    Let(name: name, value: value, in: next) -> {
      try #(value_type, value_tree, typer) = do_infer(value, environment, typer)
      let environment = push_variable(environment, name, value_type)
      try #(next_type, next_tree, typer) = do_infer(next, environment, typer)
      let tree = Let(name, #(value_type, value_tree), #(next_type, next_tree))
      Ok(#(next_type, tree, typer))
    }
    Var(name) -> {
      try var_type = fetch_variable(environment, name)
      Ok(#(var_type, Var(name), typer))
    }
  }
  //     Function(arguments, body) -> {
  //       let #(typed_arguments, state) = push_arguments(arguments, [], state)
  //       try #(return_type, tree, _) = infer(body, state)
  //       let body = #(return_type, tree)
  //       let constructor_arguments: List(Type) =
  //         typed_arguments_remove_name(typed_arguments, [return_type])
  //       Ok(#(
  //         Constructor("Function", constructor_arguments),
  //         Function(typed_arguments, body), [],
  //       ))
  //     }
  //     // Call(with) Function(for)
  //     Call(function, with) -> {
  //       try #(function_type, _, _) = infer(function, state)
  //       case function_type {
  //         Constructor("Function", for) -> {
  //             // return substitutions
  //           try #(return_type, substitutions) = unify_function_arguments(for, with, state)
  //           Ok(#(return_type, Tuple, substitutions))
  //         }
  //       }
  //     }
  //     // Ok(return_type)
  //     Var(name) -> {
  //       try var_type = find_in_env(state, name)
  //       Ok(#(var_type, Var(name), []))
  //     }
}
