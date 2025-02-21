import eyg/analysis/typ as t
import eyg/interpreter/builtin
import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/int
import gleam/order.{Eq, Gt, Lt}
import gleam/result

pub fn compare() {
  let type_ =
    t.Fun(
      t.Integer,
      t.Open(0),
      t.Fun(
        t.Integer,
        t.Open(1),
        t.Union(t.Extend(
          "Lt",
          t.unit,
          t.Extend("Eq", t.unit, t.Extend("Gt", t.unit, t.Closed)),
        )),
      ),
    )
  #(type_, state.Arity2(do_compare))
}

fn do_compare(left, right, _meta, env, k) {
  use left <- result.then(cast.as_integer(left))
  use right <- result.then(cast.as_integer(right))
  let return = case int.compare(left, right) {
    Lt -> v.Tagged("Lt", v.unit())
    Eq -> v.Tagged("Eq", v.unit())
    Gt -> v.Tagged("Gt", v.unit())
  }
  Ok(#(state.V(return), env, k))
}

pub fn add() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, builtin.add)
}

pub fn subtract() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, builtin.subtract)
}

pub fn multiply() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, builtin.multiply)
}

pub fn divide() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, builtin.divide)
}

pub fn absolute() {
  let type_ = t.Fun(t.Integer, t.Open(0), t.Integer)
  #(type_, builtin.absolute)
}

pub fn parse() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Integer)
  #(type_, state.Arity1(do_parse))
}

fn do_parse(raw, _meta, env, k) {
  use raw <- result.then(cast.as_string(raw))
  let value = case int.parse(raw) {
    Ok(i) -> v.ok(v.Integer(i))
    Error(Nil) -> v.error(v.unit())
  }
  Ok(#(state.V(value), env, k))
}

pub fn to_string() {
  let type_ = t.Fun(t.Integer, t.Open(0), t.Str)
  #(type_, builtin.int_to_string)
}
