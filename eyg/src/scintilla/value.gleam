import gleam/dict.{type Dict}
import gleam/option.{type Option}
import glance as g

type Env =
  Dict(String, Value)

pub type Value {
  I(Int)
  NegateInt
  F(Float)
  S(String)
  T(List(Value))
  L(List(Value))
  R(String, List(g.Field(Value)))
  Constructor(String, List(Option(String)))
  NegateBool
  Closure(List(g.FnParameter), List(g.Statement), Env)
  // this will be module env
  NamedClosure(List(g.FunctionParameter), List(g.Statement), Env)
  Captured(function: Value, before: List(Value), after: List(Value))
  BinaryOperator(g.BinaryOperator)
  Module(g.Module)
}

pub const nil = R("Nil", [])

pub const true = R("True", [])

pub const false = R("False", [])

pub fn bool(raw) {
  case raw {
    True -> true
    False -> false
  }
}