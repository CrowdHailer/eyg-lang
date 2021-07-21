import language

type Type {
  // Called App in Gleam
  UserType(String)
  FunctionType(arguments: List(TypeVariable), return: TypeVariable)
}

type TypeVariable {
  Unbound(Int)
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
  }
}

// Constructor
pub fn hello_world_test() {
  let initial = State([], 0)
  let ast = Let(name: "foo", value: Binary, in: Var(name: "foo"))
  assert Ok(Linked(UserType("Binary"))) = infer(ast, initial)
  assert Error(Nil) = infer(Var(name: "foo"), initial)
  let ast = Function(arguments: ["x"], body: Var(name: "x"))
  assert Ok(Linked(FunctionType(arguments: [Unbound(1)], return: Unbound(1)))) = infer(ast, initial)
  Nil
}
