import gleam/int
import gleam/order.{Eq, Gt, Lt}
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/cast

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
  #(type_, r.Arity2(do_compare))
}

fn do_compare(left, right, rev, env, k) {
  use left <- cast.require(cast.integer(left), rev, env, k)
  use right <- cast.require(cast.integer(right), rev, env, k)
  let return = case int.compare(left, right) {
    Lt -> r.Tagged("Lt", r.unit)
    Eq -> r.Tagged("Eq", r.unit)
    Gt -> r.Tagged("Gt", r.unit)
  }
  r.K(r.V(return), rev, env, k)
}

pub fn add() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, r.Arity2(do_add))
}

fn do_add(left, right, rev, env, k) {
  use left <- cast.require(cast.integer(left), rev, env, k)
  use right <- cast.require(cast.integer(right), rev, env, k)
  r.K(r.V(r.Integer(left + right)), rev, env, k)
}

pub fn subtract() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, r.Arity2(do_subtract))
}

fn do_subtract(left, right, rev, env, k) {
  use left <- cast.require(cast.integer(left), rev, env, k)
  use right <- cast.require(cast.integer(right), rev, env, k)
  r.K(r.V(r.Integer(left - right)), rev, env, k)
}

pub fn multiply() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, r.Arity2(do_multiply))
}

fn do_multiply(left, right, rev, env, k) {
  use left <- cast.require(cast.integer(left), rev, env, k)
  use right <- cast.require(cast.integer(right), rev, env, k)
  r.K(r.V(r.Integer(left * right)), rev, env, k)
}

pub fn divide() {
  let type_ =
    t.Fun(t.Integer, t.Open(0), t.Fun(t.Integer, t.Open(1), t.Integer))
  #(type_, r.Arity2(do_divide))
}

fn do_divide(left, right, rev, env, k) {
  use left <- cast.require(cast.integer(left), rev, env, k)
  use right <- cast.require(cast.integer(right), rev, env, k)
  let value = case right {
    0 -> r.error(r.unit)
    _ -> r.ok(r.Integer(left / right))
  }
  r.K(r.V(value), rev, env, k)
}

pub fn absolute() {
  let type_ = t.Fun(t.Integer, t.Open(0), t.Integer)
  #(type_, r.Arity1(do_absolute))
}

fn do_absolute(x, rev, env, k) {
  use x <- cast.require(cast.integer(x), rev, env, k)
  r.K(r.V(r.Integer(int.absolute_value(x))), rev, env, k)
}

pub fn parse() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Integer)
  #(type_, r.Arity1(do_parse))
}

fn do_parse(raw, rev, env, k) {
  use raw <- cast.require(cast.string(raw), rev, env, k)
  case int.parse(raw) {
    Ok(i) -> r.ok(r.Integer(i))
    Error(Nil) -> r.error(r.unit)
  }
  |> r.V
  |> r.K(rev, env, k)
}

pub fn to_string() {
  let type_ = t.Fun(t.Integer, t.Open(0), t.Str)
  #(type_, r.Arity1(do_to_string))
}

fn do_to_string(x, rev, env, k) {
  use x <- cast.require(cast.integer(x), rev, env, k)
  r.K(r.V(r.Str(int.to_string(x))), rev, env, k)
}
