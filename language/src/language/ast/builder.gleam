import gleam/list
import language/ast.{Assignment, Binary, Call, Case, Destructure, Fn, Let, Var}

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

pub fn clause(constructor, arguments, then) {
  #(Destructure(constructor, arguments), then)
}

pub fn rest(label, then) {
  #(Assignment(label), then)
}

pub fn function(for, in) {
  #(Nil, Fn(list.map(for, fn(name) { #(Nil, name) }), in))
}

pub fn call(function, with) {
  #(Nil, Call(function, with))
}
