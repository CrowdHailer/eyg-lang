import language

type Type {
  // Called App in Gleam
  UserType(String)
  FunctionType(arguments: List(TypeVariable), return: TypeVariable)
}

type TypeVariable {
  Unbound(Int)
  // called Named in JS guide
  Linked(Type)
}

type State {
  State(environment: List(#(String, TypeVariable)), type_variable_counter: Int)
}

type Expression {
  // Pattern is name in Let
  Let(name: String, value: Expression, in: Expression)
  Var(name: String)
  Binary
  Case
  Tuple
  // arguments are names only
  Function(arguments: List(String), body: Expression)
  Call(function: Expression, arguments: List(Expression))
}

// Be careful not to confuse substitutions with environments. 
// A substitution maps type variables to types whereas an environment maps variables (which are expressions) to types.
// Apply/Call
fn find_in_env(env, name) {
  case env {
    [] -> Error(Nil)
    [#(key, given), .._] if key == name -> Ok(given)
    [_, ..rest] -> find_in_env(rest, name)
  }
}

fn push_arguments(arguments, typed, state) {
  case arguments {
    [] -> #(typed, state)
    [name, ..rest] -> {
      let State(environment, type_variable_counter) = state
      let type_variable_counter = type_variable_counter + 1
      let type_variable = Unbound(type_variable_counter)
      let environment = [#(name, type_variable), ..environment]
      let typed = [type_variable, ..typed]
      let state = State(environment, type_variable_counter)
      push_arguments(rest, typed, state)
    }
  }
}

fn argument_types(arguments, state, typed) {
  case arguments {
    [] -> Ok(typed)
    [argument, ..rest] -> {
      try argument_type = infer(argument, state)
      argument_types(rest, state, [argument_type, ..typed])
    }
  }
}

fn unify(left, right) {
  case left, right {
    l, r if l == r -> Ok(Nil)
  }
}

// Have zip functionality
// Do we need to back trace with all the substitutions? or does calling infer at the right points get the value out that we need?
fn unify_all(lefts, rights) {
  case lefts, rights {
    [], [] -> Ok(Nil)
    [left, ..lefts], [right, ..rights] -> {
      assert Ok(Nil) = unify(left, right)
      unify_all(lefts, rights)
    }
  }
}

fn infer(node, state) {
  let State(environment, ..) = state
  case node {
    Binary -> Ok(Linked(UserType("Binary")))
    Let(name: name, value: value, in: expression) -> {
      try value_type = infer(value, state)
      let environment = [#(name, value_type), ..environment]
      let state = State(..state, environment: environment)
      infer(expression, state)
    }
    Var(name) -> find_in_env(environment, name)
    Function(arguments, body) -> {
      let #(typed_arguments, state) = push_arguments(arguments, [], state)
      try return = infer(body, state)
      Ok(Linked(FunctionType(arguments: typed_arguments, return: return)))
    }
    Call(function, arguments) -> {
      try function_type = infer(function, state)
      case function_type {
        Linked(FunctionType(expected_arguments, return)) -> {
          try actual_arguments = argument_types(arguments, state, [])
          unify_all(expected_arguments, actual_arguments)
          assert expected_arguments = actual_arguments
          case expected_arguments == actual_arguments {
            True -> Ok(return)
            False -> Error(Nil)
          }
        }
      }
    }
  }
}
// Constructor
// pub fn hello_world_test() {
//   let initial = State([], 0)
//   let ast = Let(name: "foo", value: Binary, in: Var(name: "foo"))
//   assert Ok(Linked(UserType("Binary"))) = infer(ast, initial)
//   assert Error(Nil) = infer(Var(name: "foo"), initial)
//   let ast = Function(arguments: ["x"], body: Var(name: "x"))
//   assert Ok(Linked(FunctionType(arguments: [Unbound(1)], return: Unbound(1)))) =
//     infer(ast, initial)
//   let binary_fn = Function(arguments: [], body: Binary)
//   let ast =
//     Let(
//       name: "my_fn",
//       value: binary_fn,
//       in: Call(function: Var("my_fn"), arguments: []),
//     )
//   assert Ok(Linked(UserType("Binary"))) = infer(ast, initial)
//   let ast =
//     Let(
//       name: "bin",
//       value: Binary,
//       in: Call(
//         function: Function(arguments: ["x"], body: Var(name: "x")),
//         arguments: [Var(name: "bin")],
//       ),
//     )
//   assert Ok(Linked(UserType("Binary"))) = infer(ast, initial)
//   Nil
// }
// TODO
// pub fn run_compiler_test() {
//   let Ok(_) = language.lists()
//   // let Ok(_) = language.compiler()
// }
