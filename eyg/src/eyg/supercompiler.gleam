import gleam/io
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

//   Fn(String, Control, List(#(String, Control)))
//   Residual(String)

pub type Arity {

  // I don;t want to pass in env here but I need it to be able to pass it to K
  Arity1(
    fn(Value, List(#(String, Value)), fn(Value, List(#(String, Value))) -> K) ->
      K,
  )
}

pub type Value {
  Binary(String)
  Fn(String, e.Expression, List(#(String, Value)))
  Defunc(Arity, List(Value))
  Residual(e.Expression)
}

pub type K {
  Done(e.Expression)
  K(Control, List(#(String, Value)), fn(Value, List(#(String, Value))) -> K)
}

// normal CEK eval keep path to returned function/ NO I think supercompilation is the way
// let print = fmt(foo) types from runtime
// let x = 5
// fn x -> x  needs to not return 5
// 
// let x = 4
// let x = y
// x needs to not return 4

// f x
// let y = x + x
// let z = 100
// let z = x()
// let _ = log(z)
// y

// value is always used if residual is an effect or it is a function that could effect

//   pop residual here 
// let is always something i.e. some other residual or an expression
// let is long residual don't want to copy everywhere
// keep tree the same keep let if then is not residual
// create let at beginning of lambda if residual is large

// The whole point of the supercompilation is to hit apply in lambdas
// i.e.
// fn -> fmt("%s")("hey") == fn -> "hey"
// let x = 1
// fn y -> add(x + x)(y + y)
// use makes continuations explicit in AST and so supercompilation easier

// Eval is not the goal instead it is fmt and JSON.decode
// with type providers the transpiler knew all the providers
// I need to have libraries for decode without extending the core
pub fn step(control, env, k) {
  //   io.debug(#("--", control, env, k))
  case control {
    E(e.Variable(var)) -> {
      // I think error if we insert residuals in all fns
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
            _, args -> K(V(Defunc(arity, applied)), env, k)
          }
        }

        // Arity2(impl), [x, y] -> impl(x, y, builtins, kont)
        // Arity3(impl), [x, y, z] -> impl(x, y, z, builtins, kont)
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
    E(e.Binary(b)) -> K(V(Binary(b)), env, k)
    E(e.Builtin(key)) -> K(V(Defunc(builtin(key), [])), env, k)
    V(value) -> k(value, env)
    _ -> {
      io.debug(#("control---", control))
      todo("supeswer")
    }
  }
}

fn builtin(key) {
  case key {
    "string_uppercase" -> Arity1(do_uppercase)
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

// NEED to pass expression to Defuncs
// do_match

fn to_expression(value) {
  case value {
    Binary(b) -> e.Binary(b)
    Residual(exp) -> exp
    _ -> {
      io.debug(value)
      panic("sdsd")
    }
  }
}

pub fn eval(exp) {
  do_eval(
    E(exp),
    [],
    fn(value, _e) {
      Done(case value {
        // E(exp) -> exp
        Binary(value) -> e.Binary(value)
        Fn(_, _, _) -> todo("end with fn")
        Residual(_) -> todo("residual")
        Defunc(_, _) -> todo("defun")
      })
    },
  )
}

fn do_eval(control, e, k) {
  case step(control, e, k) {
    Done(value) -> value
    K(control, e, k) -> do_eval(control, e, k)
  }
}
