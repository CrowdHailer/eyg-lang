import gleam/list
import language/ast.{
  Assignment, Binary, Call, Case, Destructure, Function, Let, Var,
}

pub fn let_(name, value, in) {
  #(Nil, Let(Assignment(name), value, in))
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
