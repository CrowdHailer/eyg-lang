import gleam/io
import gleam/list
import gleam/map
import gleam/set
import eyg/incremental/source as e
import eyg/analysis/jm/error
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/env
import eyg/analysis/jm/unify
// import harness/ffi/core
// import harness/ffi/integer
// import harness/ffi/linked_list
// import harness/ffi/string
// import eyg/analysis/typ as old_t


pub fn mono(type_)  {
  #([], type_)
}

// reference substitution env and type.
// causes circular dependencies to move to any other file
pub fn generalise(sub, env, t)  {
  let env = env.apply(sub, env)
  let t = t.apply(sub, t)
  let forall = set.drop(t.ftv(t), set.to_list(env.ftv(env)))
  #(set.to_list(forall), t)
}

pub fn instantiate(scheme, next) {
  let #(forall, type_) = scheme
  let s = list.index_map(forall, fn(i, old) { #(old, t.Var(next + i))})
  |> map.from_list()
  let next = next + list.length(forall)
  let type_ = t.apply(s, type_)
  #(type_, next)
}

pub fn extend(env, label, scheme) { 
  map.insert(env, label, scheme)
}

pub fn unify_at(type_, found, sub, next, types, ref) {
  case unify.unify(type_, found, sub, next) {
    Ok(#(s, next)) -> #(s, next, map.insert(types, ref, Ok(type_))) 
    Error(reason) -> #(sub, next, map.insert(types, ref, Error(#(reason, type_, found))))
  }
}

pub type State = #(t.Substitutions, Int, map.Map(Int, Result(t.Type, #(error.Reason, t.Type, t.Type))))

pub type Run {
  Cont(State, fn(State) -> Run)
  Done(State)
}

// this is required to make the infer function tail recursive
pub fn loop(run) {
  case run {
    Done(state) -> state
    Cont(state, k) -> loop(k(state))
  }
}

pub fn builtins()  {
  map.new()
  |> extend_b("equal", equal())
  |> extend_b("debug", debug())
  |> extend_b("fix", fix())
  // |> extend_b("fixed", fixed())
  |> extend_b("serialize", serialize())
  |> extend_b("capture", capture())
  |> extend_b("encode_uri", encode_uri())
  // integer
  |> extend_b("int_add", add())
  |> extend_b("int_subtract", subtract())
  |> extend_b("int_multiply", multiply())
  |> extend_b("int_divide", divide())
  |> extend_b("int_absolute", absolute())
  // |> extend_b("int_parse", parse())
  |> extend_b("int_to_string", to_string())
  // string
  |> extend_b("string_append", append())
  |> extend_b("string_uppercase", uppercase())
  |> extend_b("string_lowercase", lowercase())
  |> extend_b("string_length", length())
  // list
  |> extend_b("list_pop", pop())
  |> extend_b("list_fold", fold())
}



fn extend_b(env, key, t) { 
  let scheme = generalise( map.new(), map.new(), t)
  case key == "should_render" {
    False -> Nil
    True -> {
      io.debug(#(key, scheme, t))
      Nil
    }
  }
  extend(env, key, scheme)
}

// THere could be part of std
pub fn equal()  {
  t.Fun(t.Var(0), t.Var(1), t.Fun(t.Var(0), t.Var(2), t.boolean))
}

pub fn debug()  {
  t.Fun(t.Var(0), t.Var(1), t.String)
}

pub fn fix()  {
  t.Fun(
      t.Fun(t.Var(0), t.Var(1), t.Var(0)),
      t.Var(2),
      t.Var(0),
    )
}

pub fn serialize()  {
  t.Fun(t.Var(0), t.Var(1), t.String)
}

pub fn capture()  {
  t.Fun(t.Var(0), t.Var(1), t.Var(2))
}

pub fn encode_uri()  {
  t.Fun(t.String, t.Var(1), t.String)
}

// int
// TODO fn2 taking a next would make handling curried fns easier
pub fn add()  {
  t.Fun(t.Integer, t.Var(0), t.Fun(t.Integer, t.Var(1), t.Integer))
}

pub fn subtract()  {
  t.Fun(t.Integer, t.Var(0), t.Fun(t.Integer, t.Var(1), t.Integer))
}

pub fn multiply()  {
  t.Fun(t.Integer, t.Var(0), t.Fun(t.Integer, t.Var(1), t.Integer))
}

pub fn divide()  {
  t.Fun(t.Integer, t.Var(0), t.Fun(t.Integer, t.Var(1), t.Integer))
}

pub fn absolute()  {
  t.Fun(t.Integer, t.Var(0), t.Integer)
}

// TODO parse

pub fn to_string()  {
  t.Fun(t.Integer, t.Var(0), t.String)
}

pub fn append()  {
  t.Fun(t.String, t.Var(0), t.Fun(t.String, t.Var(1), t.String))
}

pub fn uppercase()  {
  t.Fun(t.String, t.Var(0), t.String)
}

pub fn lowercase()  {
  t.Fun(t.String, t.Var(0), t.String)
}

pub fn length()  {
  t.Fun(t.String, t.Var(0), t.Integer)
}

pub fn pop()  {
  let parts =
    t.Record(t.RowExtend(
      "head",
      t.Var(0),
      t.RowExtend("tail", t.LinkedList(t.Var(0)), t.Empty),
    ))
  t.Fun(t.LinkedList(t.Var(0)), t.Var(1), t.result(parts, t.unit))
}

pub fn fold() {
  let item = t.Var(0)
  let eff1 = t.Var(1)
  let acc = t.Var(2)
  let eff2 = t.Var(3)
  let eff3 = t.Var(4)
  let eff4 = t.Var(5)
  let eff5 = t.Var(6)

  t.Fun(
    t.LinkedList(item),
    eff1,
    t.Fun(
      acc,
      eff2,
      t.Fun(
        t.Fun(
          item,
          eff3,
          t.Fun(acc, eff4, acc),
        ),
        eff5,
        acc,
      ),
    ),
  )
}