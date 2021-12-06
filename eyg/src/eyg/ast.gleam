import gleam/int
import gleam/list
import gleam/string
import eyg/typer/monotype
import eyg/ast/provider
import eyg/ast/expression

pub fn binary(value) {
  #(Nil, expression.Binary(value))
}

pub fn call(function, with) {
  #(Nil, expression.Call(function, with))
}

pub fn function(for, body) {
  #(Nil, expression.Function(for, body))
}

pub fn let_(pattern, value, then) {
  #(Nil, expression.Let(pattern, value, then))
}

pub fn tuple_(elements) {
  #(Nil, expression.Tuple(elements))
}

pub fn row(fields) {
  #(Nil, expression.Row(fields))
}

pub fn variable(label) {
  #(Nil, expression.Variable(label))
}

pub fn provider(config, generator) {
  #(Nil, expression.Provider(config, generator))
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
