import gleam/int
import gleam/list
import gleam/string
import eyg/ast/provider
import eyg/ast/expression as e

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
  #(Nil, e.Provider(config, generator))
}

pub fn generate_hole(_config, _type) {
  binary(
    "this is assumed to never be called, just a flag for implementing holes as a provider",
  )
}

pub fn hole() {
  provider("", generate_hole)
}

// can't use this in guards
pub fn is_hole(generator) {
  generator == generate_hole
}
