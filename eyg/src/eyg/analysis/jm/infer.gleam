import eyg/analysis/jm/env
import eyg/analysis/jm/error
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/unify
import gleam/dict
import gleam/list
import gleam/set

pub fn mono(type_) {
  #([], type_)
}

// reference substitution env and type.
// causes circular dependencies to move to any other file
pub fn generalise(sub, env, t) {
  let env = env.apply(sub, env)
  let t = t.apply(sub, t)
  let forall = set.drop(t.ftv(t), set.to_list(env.ftv(env)))
  #(set.to_list(forall), t)
}

pub fn instantiate(scheme, next) {
  // TODO, I don't know why I increase this by 1000. I think it was for debugging and it should be removed
  let next = next + 1000
  let #(forall, type_) = scheme
  let s =
    list.index_map(forall, fn(i, old) { #(old, t.Var(next + i)) })
    |> dict.from_list()
  let next = next + list.length(forall)
  // Apply is actually on a recursive substitution, composing SHOULD update all values to make it a single call
  let type_ = apply_once(s, type_)

  #(type_, next)
}

fn apply_once(s, type_) {
  case type_ {
    // This is recursive, get to the bottom of this
    t.Var(a) ->
      case dict.get(s, a) {
        Ok(new) -> new
        Error(Nil) -> type_
      }
    t.Fun(from, effects, to) ->
      t.Fun(apply_once(s, from), apply_once(s, effects), apply_once(s, to))
    t.Binary | t.Integer | t.String -> type_
    t.LinkedList(element) -> t.LinkedList(apply_once(s, element))
    t.Record(row) -> t.Record(apply_once(s, row))
    t.Union(row) -> t.Union(apply_once(s, row))
    t.Empty -> type_
    t.RowExtend(label, value, rest) ->
      t.RowExtend(label, apply_once(s, value), apply_once(s, rest))
    t.EffectExtend(label, #(lift, reply), rest) ->
      t.EffectExtend(
        label,
        #(apply_once(s, lift), apply_once(s, reply)),
        apply_once(s, rest),
      )
  }
}

pub fn extend(env, label, scheme) {
  dict.insert(env, label, scheme)
}

pub fn unify_at(type_, found, sub, next, types, ref) {
  case unify.unify(type_, found, sub, next) {
    Ok(#(s, next)) -> #(s, next, dict.insert(types, ref, Ok(type_)))
    Error(reason) -> #(
      sub,
      next,
      dict.insert(types, ref, Error(#(reason, type_, found))),
    )
  }
}

pub type State =
  #(
    t.Substitutions,
    Int,
    dict.Dict(Int, Result(t.Type, #(error.Reason, t.Type, t.Type))),
  )

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

pub fn fetch(env, x, sub, next, types, ref, type_, k) {
  case dict.get(env, x) {
    Ok(scheme) -> {
      let #(found, next) = instantiate(scheme, next)
      Cont(unify_at(type_, found, sub, next, types, ref), k)
    }
    Error(Nil) -> {
      let #(unmatched, next) = t.fresh(next)
      let types =
        dict.insert(
          types,
          ref,
          Error(#(error.MissingVariable(x), type_, unmatched)),
        )
      Cont(#(sub, next, types), k)
    }
  }
}

pub fn builtins() {
  dict.new()
  |> extend_b("equal", equal())
  |> extend_b("debug", debug())
  |> extend_b("fix", fix())
  |> extend_b("eval", eval())
  // |> extend_b("fixed", fixed())
  |> extend_b("serialize", serialize())
  |> extend_b("capture", capture())
  |> extend_b("encode_uri", encode_uri())
  // integer
  |> extend_b("int_add", add())
  |> extend_b("int_subtract", subtract())
  |> extend_b("int_multiply", multiply())
  |> extend_b("int_divide", divide())
  // |> extend_b("int_parse", parse())
  |> extend_b("int_to_string", to_string())
  // string
  |> extend_b("string_append", append())
  |> extend_b("string_replace", replace())
  |> extend_b("string_split", split())
  |> extend_b("string_uppercase", uppercase())
  |> extend_b("string_lowercase", lowercase())
  |> extend_b("string_length", length())
  |> extend_b("pop_grapheme", pop_grapheme())
  // list
  |> extend_b("list_pop", pop())
  |> extend_b("list_fold", fold())
}

fn extend_b(env, key, t) {
  let scheme = generalise(dict.new(), dict.new(), t)
  extend(env, key, scheme)
}

// THere could be part of std
pub fn equal() {
  t.Fun(t.Var(0), t.Var(1), t.Fun(t.Var(0), t.Var(2), t.boolean))
}

pub fn debug() {
  t.Fun(t.Var(0), t.Var(1), t.String)
}

pub fn fix() {
  t.Fun(t.Fun(t.Var(0), t.Var(1), t.Var(0)), t.Var(2), t.Var(0))
}

pub fn eval() {
  // could raise eval effect to ensure type checking is sound
  t.Fun(t.Var(0), t.Var(1), t.Var(2))
}

pub fn serialize() {
  t.Fun(t.Var(0), t.Var(1), t.String)
}

pub fn capture() {
  t.Fun(t.Var(0), t.Var(1), t.Var(2))
}

pub fn encode_uri() {
  t.Fun(t.String, t.Var(1), t.String)
}

// int
// TODO fn2 taking a next would make handling curried fns easier
pub fn add() {
  t.Fun(t.Integer, t.Var(0), t.Fun(t.Integer, t.Var(1), t.Integer))
}

pub fn subtract() {
  t.Fun(t.Integer, t.Var(0), t.Fun(t.Integer, t.Var(1), t.Integer))
}

pub fn multiply() {
  t.Fun(t.Integer, t.Var(0), t.Fun(t.Integer, t.Var(1), t.Integer))
}

pub fn divide() {
  t.Fun(t.Integer, t.Var(0), t.Fun(t.Integer, t.Var(1), t.Integer))
}

// TODO parse

pub fn to_string() {
  t.Fun(t.Integer, t.Var(0), t.String)
}

pub fn append() {
  t.Fun(t.String, t.Var(0), t.Fun(t.String, t.Var(1), t.String))
}

pub fn replace() {
  t.Fun(
    t.String,
    t.Var(0),
    t.Fun(t.String, t.Var(1), t.Fun(t.String, t.Var(2), t.String)),
  )
}

pub fn split() {
  t.Fun(
    t.String,
    t.Var(0),
    t.Fun(
      t.String,
      t.Var(1),
      t.Record(t.RowExtend(
        "head",
        t.String,
        t.RowExtend("tail", t.LinkedList(t.String), t.Empty),
      )),
    ),
  )
}

// append(append(foo, x), bar)

pub fn uppercase() {
  t.Fun(t.String, t.Var(0), t.String)
}

pub fn lowercase() {
  t.Fun(t.String, t.Var(0), t.String)
}

pub fn length() {
  t.Fun(t.String, t.Var(0), t.Integer)
}

pub fn pop_grapheme() {
  let parts =
    t.Record(t.RowExtend(
      "head",
      t.String,
      t.RowExtend("tail", t.String, t.Empty),
    ))
  t.Fun(t.String, t.Var(0), t.result(parts, t.unit))
}

pub fn pop() {
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
    t.Fun(acc, eff2, t.Fun(t.Fun(item, eff3, t.Fun(acc, eff4, acc)), eff5, acc)),
  )
}
