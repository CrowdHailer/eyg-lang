import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import eyg/ast/provider
import eyg/ast/expression as e
import eyg/ast/pattern as p

pub fn binary(value) {
  #(dynamic.from(Nil), e.Binary(value))
}

pub fn call(function, with) {
  #(dynamic.from(Nil), e.Call(function, with))
}

pub fn case_(value, branches) {
  #(dynamic.from(Nil), e.Case(value, branches))
}

pub fn function(for, body) {
  #(dynamic.from(Nil), e.Function(for, body))
}

pub fn let_(pattern, value, then) {
  #(dynamic.from(Nil), e.Let(pattern, value, then))
}

pub fn tuple_(elements) {
  #(dynamic.from(Nil), e.Tuple(elements))
}

pub fn row(fields) {
  #(dynamic.from(Nil), e.Row(fields))
}

pub fn variable(label) {
  #(dynamic.from(Nil), e.Variable(label))
}

pub fn provider(config, generator) {
  #(dynamic.from(Nil), e.Provider(config, generator, dynamic.from(Nil)))
}

pub fn hole() {
  provider("", e.Hole)
}

pub fn is_hole(generator) {
  generator == e.Hole
}
