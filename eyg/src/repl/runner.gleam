import gleam/dict
import gleam/float
import gleam/int
import gleam/io
import gleam/option.{None}
import gleam/result.{try}
import glance as g

// needs testing
pub fn exec(statement, env) {
  do_exec(statement, env, [])
}

fn do_exec(statement, env, ks) {
  case statement {
    g.Expression(exp) -> do_eval(exp, env, ks)

    _ -> Error("not support")
  }
}

fn do_eval(exp, env, ks) {
  case exp {
    g.Int(raw) -> {
      let assert Ok(v) = int.parse(raw)
      apply(I(v), env, ks)
    }
    g.Float(raw) -> {
      let assert Ok(v) = float.parse(raw)
      apply(F(v), env, ks)
    }
    // Why are these not their own type
    g.Variable("True") -> apply(B(True), env, ks)
    g.Variable("False") -> apply(B(False), env, ks)
    g.String(raw) -> apply(S(raw), env, ks)
    // TODO rename Negate number
    g.NegateInt(g.Int(raw)) -> {
      let assert Ok(v) = int.parse(raw)
      apply(I(-v), env, ks)
    }
    g.NegateInt(g.Float(raw)) -> {
      let assert Ok(v) = float.parse(raw)
      apply(F(-1.0 *. v), env, ks)
    }
    g.NegateBool(exp) ->
      do_eval(exp, env, [Apply(Builtin(Arity1(negate_bool), [])), ..ks])
    g.Panic(message) -> todo("message")
    g.Todo(message) -> todo("todo message")
    g.Tuple([]) -> apply(T([]), env, ks)
    // g.Tuple(elements) -> do_eval[Apply(Builtin(TupleConstructor()))]
    // g.List()
    g.Fn(args, _annotation, body) -> apply(Closure(args, body, env), env, ks)
    // TODO real arguments
    // TODO handle labeled arguments
    g.Call(function, [g.Field(None, argument)]) ->
      do_eval(function, env, [Arg(argument), ..ks])
    g.BinaryOperator(name, left, right) -> {
      let impl = bin_impl(name)
      do_eval(left, env, [Apply(Builtin(Arity2(impl), [])), Arg(right), ..ks])
    }
    _ -> {
      io.debug(#("unsupported ", exp))
      todo("not supported")
    }
  }
}

fn apply(value, env, ks) {
  case ks {
    [] -> Ok(value)
    [Apply(func), ..ks] -> {
      let assert Ok(next) = call(func, value)
      apply(next, env, ks)
    }
    [Arg(exp), ..ks] -> do_eval(exp, env, [Apply(value), ..ks])
    _ -> {
      io.debug(#(value, ks))
      todo("bad apply")
    }
  }
}

fn call(func, last) {
  case func {
    Closure(params, body, captured) -> {
      // as long as closure keeps returning itself until full of arguments
      io.debug(params)
      todo("real application")
    }
    Builtin(Arity1(impl), []) -> impl(last)
    Builtin(Arity2(impl), [a]) -> impl(a, last)
    Builtin(Arity2(impl), args) -> Ok(Builtin(Arity2(impl), [last, ..args]))
    I(_) -> Error("not a function")
  }
}

fn negate_bool(in) {
  use in <- try(as_boolean(in))
  Ok(B(!in))
}

fn bin_impl(name) {
  case name {
    g.And -> fn(a, b) {
      use a <- try(as_boolean(a))
      use b <- try(as_boolean(b))
      Ok(B(a && b))
    }
    g.Or -> fn(a, b) {
      use a <- try(as_boolean(a))
      use b <- try(as_boolean(b))
      Ok(B(a || b))
    }
    g.Eq -> fn(a, b) { Ok(B(a == b)) }
    g.NotEq -> fn(a, b) { Ok(B(a != b)) }
    g.LtInt -> fn(a, b) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      Ok(B(a < b))
    }
    g.LtEqInt -> fn(a, b) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      Ok(B(a <= b))
    }
    g.LtFloat -> fn(a, b) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      Ok(B(a <. b))
    }
    g.LtEqFloat -> fn(a, b) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      Ok(B(a <=. b))
    }
    g.GtEqInt -> fn(a, b) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      Ok(B(a >= b))
    }
    g.GtInt -> fn(a, b) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      Ok(B(a > b))
    }
    g.GtEqFloat -> fn(a, b) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      Ok(B(a >=. b))
    }
    g.GtFloat -> fn(a, b) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      Ok(B(a >. b))
    }
    g.AddInt -> fn(a, b) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      Ok(I(a + b))
    }
    g.AddFloat -> fn(a, b) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      Ok(F(a +. b))
    }
    g.SubInt -> fn(a, b) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      Ok(I(a - b))
    }
    g.SubFloat -> fn(a, b) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      Ok(F(a -. b))
    }
    g.MultInt -> fn(a, b) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      Ok(I(a * b))
    }
    g.MultFloat -> fn(a, b) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      Ok(F(a *. b))
    }
    g.DivInt -> fn(a, b) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      Ok(I(a / b))
    }
    g.DivFloat -> fn(a, b) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      Ok(F(a /. b))
    }
    g.RemainderInt -> fn(a, b) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      Ok(I(a % b))
    }
    g.Concatenate -> fn(a, b) {
      use a <- try(as_string(a))
      use b <- try(as_string(b))
      Ok(S(a <> b))
    }
  }
}

fn as_integer(value) {
  case value {
    I(value) -> Ok(value)
    _ -> Error("not an integer")
  }
}

fn as_float(value) {
  case value {
    F(value) -> Ok(value)
    _ -> Error("not an float")
  }
}

fn as_boolean(value) {
  case value {
    B(value) -> Ok(value)
    _ -> Error("not an boolean")
  }
}

fn as_string(value) {
  case value {
    S(value) -> Ok(value)
    _ -> Error("not an float")
  }
}

pub type Value {
  I(Int)
  F(Float)
  B(Bool)
  S(String)
  T(List(Value))
  Closure(List(g.FnParameter), List(g.Statement), dict.Dict(String, Value))
  Builtin(Arity, List(Value))
}

pub type Arity {
  TupleConstructor(size: Int, gathered: List(Value))
  Arity1(fn(Value) -> Result(Value, String))
  Arity2(fn(Value, Value) -> Result(Value, String))
}

pub type K {
  Apply(Value)
  Arg(g.Expression)
}
