import gleam/list
import language/ast.{Let, Var, Binary, Case, Function, Call, Destructure, Name}

pub fn let_(name, value, in) {
  #(Nil, Let(Name(name), value, in))
}

pub fn destructure(constructor, arguments, value, in) {
  #(Nil, Let(Destructure(constructor, arguments), value, in))
}

pub fn var(name) {
  #(Nil, Var(name))
}

pub fn binary() {
  #(Nil, Binary)
}

pub fn case_(subject, clauses) {
  #(Nil, Case(subject, clauses))
}

pub fn function(for, in) {
  #(Nil, Function(list.map(for, fn(name) { #(Nil, name) }), in))
}

pub fn call(function, with) {
  #(Nil, Call(function, with))
}