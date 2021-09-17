import gleam/int
import gleam/list
import gleam/string
import eyg/typer/monotype
import eyg/ast/provider
import eyg/ast/expression

pub fn binary(value) {
  #(Nil, expression.Binary(value))
}

pub fn name(type_, then) {
  #(Nil, expression.Name(type_, then))
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

pub fn case_(named, subject, clauses) {
  #(Nil, expression.Case(named, subject, clauses))
}

pub fn constructor(named, variant) {
  #(Nil, expression.Constructor(named, variant))
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

fn generate_hole(_config, _type) {
  binary("TODO this is no implemented")
}

pub fn hole() {
  provider("", generate_hole)
}

pub fn is_hole(generator) {
  generator == generate_hole
}

pub fn append_path(path, i) {
  list.append(path, [i])
}

