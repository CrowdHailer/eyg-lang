import gleam/io
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/map
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/runtime/capture
import harness/stdlib

pub type Control {
  E(e.Expression)
  V(Value)
}

type Env =
  List(#(String, Value))

pub type Arity {
  // I don;t want to pass in env here but I need it to be able to pass it to K
  Arity1(fn(Value, Env, fn(Value, Env) -> K) -> K)
  Arity2(fn(Value, Value, Env, fn(Value, Env) -> K) -> K)
  Arity3(fn(Value, Value, Value, Env, fn(Value, Env) -> K) -> K)
}

pub type Value {
  Integer(Int)
  Binary(String)
  Fn(String, e.Expression, Env)
  Defunc(Arity, List(Value))
  Residual(e.Expression)
}

pub type K {
  Done(e.Expression)
  K(Control, Env, fn(Value, Env) -> K)
}

pub fn step(control, env, k) {
  case control {
    E(e.Variable(var)) -> {
      let assert Ok(value) = list.key_find(env, var)
      K(V(value), env, k)
    }
    E(e.Lambda(param, body)) -> {
      let env = [#(param, Residual(e.Variable(param))), ..env]
      use body, _env <- K(E(body), env)
      K(V(Fn(param, to_expression(body), env)), env, k)
    }
    E(e.Apply(func, arg)) -> {
      use func, env <- K(E(func), env)
      use arg, env <- K(E(arg), env)
      case func {
        Fn(param, body, captured) -> K(E(body), [#(param, arg), ..captured], k)
        Defunc(arity, applied) -> {
          let applied = list.append(applied, [arg])
          case arity, applied {
            Arity1(impl), [x] -> impl(x, env, k)
            Arity2(impl), [x, y] -> impl(x, y, env, k)
            Arity3(impl), [x, y, z] -> impl(x, y, z, env, k)
            _, args -> K(V(Defunc(arity, applied)), env, k)
          }
        }
        _ -> {
          io.debug(func)
          todo("in apply")
        }
      }
    }
    E(e.Let(label, body, then)) -> {
      use value, env <- K(E(body), env)
      K(E(then), [#(label, value), ..env], k)
    }
    E(e.Integer(i)) -> K(V(Integer(i)), env, k)
    E(e.Binary(b)) -> K(V(Binary(b)), env, k)
    E(e.Builtin(key)) -> K(V(Defunc(builtin(key), [])), env, k)
    V(value) -> k(value, env)
    _ -> {
      io.debug(#("control---", control))
      todo("supeswer")
    }
  }
}

fn to_expression(value) {
  case value {
    Integer(i) -> e.Integer(i)
    Binary(b) -> e.Binary(b)
    Fn(param, body, _env) -> e.Lambda(param, body)
    Defunc(arity, applied) -> todo("defunc")
    Residual(exp) -> exp
  }
}

pub fn eval(exp) {
  do_eval(E(exp), [], fn(value, _e) { Done(to_expression(value)) })
}

fn do_eval(control, e, k) {
  case step(control, e, k) {
    Done(value) -> value
    K(control, e, k) -> do_eval(control, e, k)
  }
}

fn builtin(key) {
  case key {
    "string_uppercase" -> Arity1(do_uppercase)
    "integer_absolute" -> Arity1(do_absolute)
    "integer_add" -> Arity2(do_add)
  }
}

pub fn do_uppercase(v, env, k) {
  let v = case v {
    Binary(b) -> Binary(string.uppercase(b))
    Residual(e) -> Residual(e.Apply(e.Builtin("string_uppercase"), e))
    _ -> panic("invalid")
  }
  k(v, env)
}

pub fn do_absolute(v, env, k) {
  let v = case v {
    Integer(i) -> Integer(int.absolute_value(i))
    Residual(e) -> Residual(e.Apply(e.Builtin("integer_absolute"), e))
    _ -> panic("invalid")
  }
  k(v, env)
}

pub fn do_add(x, y, env, k) {
  let v = case x, y {
    Integer(i), Integer(j) -> Integer(i + j)
    Residual(x), Integer(j) ->
      Residual(e.Apply(e.Apply(e.Builtin("integer_add"), x), e.Integer(j)))
    Integer(i), Residual(y) ->
      Residual(e.Apply(e.Apply(e.Builtin("integer_add"), e.Integer(i)), y))
    Residual(x), Residual(y) ->
      Residual(e.Apply(e.Apply(e.Builtin("integer_add"), x), y))
    _, _ -> panic("invalid")
  }
  k(v, env)
}
// NEED to pass expression to Defuncs
// do_match
