import gleam/int
import gleam/io
import gleam/list
import gleam/string
import eyg/ast/provider
import eyg/ast/expression as e
import eyg/ast/pattern as p

pub fn binary(value) {
  #(Nil, e.Binary(value))
}

pub fn call(function, with) {
  #(Nil, e.Call(function, with))
}

pub fn function(for, body) {
  #(Nil, e.Function(for, body))
}

pub fn let_(pattern, value, then) {
  #(Nil, e.Let(pattern, value, then))
}

pub fn tuple_(elements) {
  #(Nil, e.Tuple(elements))
}

pub fn row(fields) {
  #(Nil, e.Row(fields))
}

pub fn variable(label) {
  #(Nil, e.Variable(label))
}

pub fn provider(config, generator) {
  #(Nil, e.Provider(config, generator, Nil))
}

pub fn hole() {
  provider("", e.Hole)
}

pub fn is_hole(generator) {
  generator == e.Hole
}
