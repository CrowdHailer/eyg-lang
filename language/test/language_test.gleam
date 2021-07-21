import language

type Expression {
  // Pattern is name in Let
  Let(name: String, value: Expression, in: Expression)
  Var(name: String)
  Binary
  Case
  Tuple
}

fn find_in_env(env, name) { 
  case env {
    [] -> Error(Nil)
    [#(key, given), ..] if key == name -> Ok(given)
    [_, ..rest] -> find_in_env(rest, name)
  }
 }

fn infer(node, env) {
  case node {
    Binary -> Ok("Binary")
    Let(name: name, value: value, in: expression) -> {
      try value_type = infer(value, env)
      let env = [#(name, value_type), ..env]
      infer(expression, env)
    }
    Var(name) ->
      find_in_env(env, name)

  }
}

// Constructor
pub fn hello_world_test() {
  let ast = Let(name: "foo", value: Binary, in: Var(name: "foo"))
  assert Ok("Binary") = infer(ast, [])
  assert Error(Nil) = infer(Var(name: "foo"), [])
  Nil
}
