// TODO rename level_j
import gleam/dict.{type Dict}
import gleam/io
import gleam/int
import gleam/list
import gleam/string
import eygir/expression as e

pub type Reason {
  MissingVariable(String)
  // TypeMismatch(t.Type, t.Type)
  // RowMismatch(String)
  // InvalidTail(t.Type)
  // RecursiveType
}

pub type Type(var) {
  Var(key: var)
  Fun(Type(var), Type(var), Type(var))
  Binary
  Integer
  String
  List(Type(var))
  // Types Record/Union must be Empty/Extend/Var
  Record(Type(var))
  Union(Type(var))
  Empty
  RowExtend(String, Type(var), Type(var))
  EffectExtend(String, #(Type(var), Type(var)), Type(var))
}

pub type Binding {
  Unbound(level: Int)
  Bound(Type(Int))
}

type State {
  State(current_typevar: Int, current_level: Int, bindings: Dict(Int, Binding))
}

pub fn infer(source) {
  let #(state, type_, eff_, acc) = do_infer(source, [], State(0, 1, dict.new()))
  #(acc, state.bindings)
}

fn new(state: State, v) {
  let State(tvar, level, bindings) = state
  let t = v(tvar)
  let bindings = dict.insert(bindings, tvar, Unbound(level))
  let tvar = tvar + 1
  let state = State(tvar, level, bindings)
  #(state, t)
}

fn newvar(state) {
  new(state, Var)
}

fn newparam(state) {
  new(state, fn(tv) { Var(#(False, tv)) })
}

fn enter_level(state: State) {
  State(..state, current_level: state.current_level + 1)
}

fn exit_level(state: State) {
  State(..state, current_level: state.current_level - 1)
}

fn gen(type_, s: State) {
  let level = s.current_level
  case type_ {
    Var(i) -> {
      let assert Ok(binding) = dict.get(s.bindings, i)
      case binding {
        Unbound(l) -> {
          // let binding = Unbound(int.min(l, level))
          // let s = dict.insert(s.bindings, i, binding)
          // #(s, Var(#))
          case l > level {
            True -> Var(#(True, i))
            False -> Var(#(False, i))
          }
        }
        Bound(t) -> gen(t, s)
      }
    }
    Fun(arg, eff, ret) -> {
      let arg = gen(arg, s)
      let eff = gen(eff, s)
      let ret = gen(ret, s)
      Fun(arg, eff, ret)
    }
    Integer -> Integer
    Binary -> Binary
    String -> String
    Empty -> Empty
    _ -> {
      io.debug(#("gen", type_))
      panic as "gen"
    }
  }
}

fn instantiate(poly, state) {
  // case poly {
  //   // How do I make this the same quantification
  //   Var(#(True, i)) ->
  // }
  let #(mono, _, state) = do_instantiate(poly, dict.new(), state)
  #(state, mono)
}

fn do_instantiate(poly, subst, state) {
  case poly {
    // How do I make this the same quantification
    Var(#(True, i)) ->
      case dict.get(subst, i) {
        Ok(tv) -> #(tv, subst, state)
        Error(Nil) -> {
          let #(state, tv) = newvar(state)
          let subst = dict.insert(subst, i, tv)
          #(tv, subst, state)
        }
      }
    Var(#(False, i)) -> #(Var(i), subst, state)
    Fun(arg, eff, ret) -> {
      let #(arg, subst, state) = do_instantiate(arg, subst, state)
      let #(eff, subst, state) = do_instantiate(eff, subst, state)
      let #(ret, subst, state) = do_instantiate(ret, subst, state)
      #(Fun(arg, eff, ret), subst, state)
    }
    Integer -> #(Integer, subst, state)
    Binary -> #(Binary, subst, state)
    String -> #(String, subst, state)
    Empty -> #(Empty, subst, state)
    _ -> {
      io.debug(#("do_inst", poly))
      panic as "inst"
    }
  }
}

// Don't generalise only ever gets passed a new Var
fn dont(type_) {
  map_tvar(type_, fn(i) { #(False, i) })
}

// Does this compose with state monad
fn map_tvar(type_, f) {
  case type_ {
    Var(x) -> Var(f(x))
  }
}

fn open_effect(eff, s) {
  case eff {
    Empty -> newvar(s)
    EffectExtend(label, type_, eff) -> {
      let #(s, eff) = open_effect(eff, s)
      #(s, EffectExtend(label, type_, eff))
    }
    other -> #(s, other)
  }
}

fn open(type_, s) {
  case type_ {
    Fun(args, eff, ret) -> {
      let #(s, eff) = open_effect(eff, s)
      let #(s, ret) = open(ret, s)
      #(s, Fun(args, eff, ret))
    }
    other -> #(s, other)
  }
}

// close should be done at a level

// Dont try and be cleever with putting on acc as
// really large effect envs still often put nothin on the acc
fn do_infer(source, env, s) {
  case source {
    e.Variable(x) ->
      case list.key_find(env, x) {
        Ok(scheme) -> {
          let #(s, type_) = instantiate(scheme, s)
          // let #(s, type_) = open(type_, s)
          #(s, type_, Empty, [#(Ok(type_), Empty, env)])
        }

        Error(Nil) -> {
          let #(s, type_) = newvar(s)
          #(s, type_, Empty, [#(Error(MissingVariable(x)), Empty, env)])
        }
      }
    e.Lambda(x, body) -> {
      let #(s, type_x) = newvar(s)
      let #(s, type_r, eff, inner) =
        do_infer(body, [#(x, dont(type_x)), ..env], s)
      let type_ = Fun(type_x, eff, type_r)
      #(s, type_, Empty, [#(Ok(type_), Empty, env), ..inner])
    }
    e.Apply(fun, arg) -> {
      // if arg and or fun have created effects then we need to unify the danger is in closing
      // can only close when we have
      //   // type is ret effect is args
      //   // can't push a tvar in early here because it might be an errorx
      let #(s, ty_fun, eff_fun, inner_fun) = do_infer(fun, env, s)
      let #(s, ty_arg, eff_arg, inner_arg) = do_infer(arg, env, s)
      let s = unify(eff_fun, eff_arg, s)
      // TODO open ty_fun
      let inner = list.append(inner_fun, inner_arg)
      let #(s, ty_ret) = newvar(s)
      let #(s, ty_eff) = newvar(s)
      let s = unify(Fun(ty_arg, ty_eff, ty_ret), ty_fun, s)
      // maybe effect mismatching shows up here. How does unison back trace
      // I guess all calls then unify with a space
      // shouldn't ever have open functions at the top level
      // Could return a non empty list and always push so that I don't need to assert on list when final thing returns

      // unify_effect just does nothing if closed
      // but they are not always aditive what if I have a function that takes an f as an arg that should be closed
      // grow effects is noth the same as unify
      // }

      #(s, ty_ret, ty_eff, [#(Ok(ty_ret), ty_eff, env), ..inner])
    }
    // This has two places that create effects but in the acc I don't want any effects
    e.Let(label, value, then) -> {
      let s = enter_level(s)
      let #(s, ty_value, eff_value, inner_value) = do_infer(value, env, s)
      let s = exit_level(s)
      let #(s, ty_then, eff_then, inner_then) =
        do_infer(then, [#(label, gen(ty_value, s)), ..env], s)
      let s = unify(eff_value, eff_then, s)
      let inner = list.append(inner_value, inner_then)
      #(s, ty_then, eff_then, [#(Ok(ty_then), Empty, env), ..inner])
    }
    e.Integer(_) -> #(s, Integer, Empty, [#(Ok(Integer), Empty, env)])
    e.Binary(_) -> #(s, String, Empty, [#(Ok(Binary), Empty, env)])
    e.Str(_) -> #(s, String, Empty, [#(Ok(String), Empty, env)])
    e.Tail -> {
      let #(s, el) = newvar(s)
      #(s, List(el), Empty, [#(Ok(List(el)), Empty, env)])
    }
    e.Cons -> {
      let #(s, el) = newvar(s)
      let list = List(el)
      let type_ = pure2(el, list, list)
      #(s, type_, Empty, [#(Ok(type_), Empty, env)])
      // TODO move to primitive
    }
    e.Empty -> #(s, Record(Empty), Empty, [#(Ok(Record(Empty)), Empty, env)])

    e.Extend(label) -> {
      let #(s, field) = newvar(s)
      let #(s, rest) = newvar(s)

      let type_ =
        pure2(field, Record(rest), Record(RowExtend(label, field, rest)))
      #(s, type_, Empty, [#(Ok(type_), Empty, env)])
    }
    e.Select(label) -> {
      let #(s, field) = newvar(s)
      let #(s, rest) = newvar(s)

      let type_ = pure1(Record(RowExtend(label, field, rest)), field)
      #(s, type_, Empty, [#(Ok(type_), Empty, env)])
    }
    e.Tag(label) -> {
      let #(s, inner) = newvar(s)
      let #(s, rest) = newvar(s)
      let type_ = pure1(inner, Union(RowExtend(label, inner, rest)))
      #(s, type_, Empty, [#(Ok(type_), Empty, env)])
    }

    e.Perform(label) -> {
      let #(s, arg) = newvar(s)
      // Do this one level lower, but Do row rewriting
      let #(s, rest) = newvar(s)
      let #(s, ret) = newvar(s)
      let type_ = Fun(arg, EffectExtend(label, #(arg, ret), rest), ret)
      #(s, type_, Empty, [#(Ok(type_), Empty, env)])
    }
    e.Builtin(label) -> {
      let type_ = primitive(label)
      #(s, type_, Empty, [#(Ok(type_), Empty, env)])
    }
    _ -> {
      io.debug(source)
      panic as "unspeorted"
    }
  }
}

fn pure1(arg1, ret) {
  Fun(arg1, Empty, ret)
}

fn pure2(arg1, arg2, ret) {
  Fun(arg1, Empty, Fun(arg2, Empty, ret))
}

fn primitive(name) {
  case name {
    "integer_add" -> pure2(Integer, Integer, Integer)
  }
}

pub fn resolve(type_, bindings) {
  case type_ {
    Var(i) -> {
      let assert Ok(binding) = dict.get(bindings, i)
      case binding {
        Bound(type_) -> resolve(type_, bindings)
        _ -> type_
      }
    }
    Fun(arg, eff, ret) ->
      Fun(
        resolve(arg, bindings),
        resolve(eff, bindings),
        resolve(ret, bindings),
      )
    Integer -> Integer
    String -> String
    Empty -> Empty
    List(el) -> List(resolve(el, bindings))
    Record(rows) -> Record(resolve(rows, bindings))
    Union(rows) -> Union(resolve(rows, bindings))
    RowExtend(label, field, rest) ->
      RowExtend(label, resolve(field, bindings), resolve(rest, bindings))
    EffectExtend(label, #(lift, reply), rest) ->
      EffectExtend(
        label,
        #(resolve(lift, bindings), resolve(reply, bindings)),
        resolve(rest, bindings),
      )
    _ -> {
      io.debug(type_)
      panic as "resolve"
    }
  }
}

fn find(type_, s: State) {
  case type_ {
    Var(i) -> dict.get(s.bindings, i)
    other -> Error(Nil)
  }
}

fn unify(t1, t2, s: State) {
  case t1, find(t1, s), t2, find(t2, s) {
    _, Ok(Bound(t1)), _, _ -> unify(t1, t2, s)
    _, _, _, Ok(Bound(t2)) -> unify(t1, t2, s)
    Var(i), _, Var(j), _ if i == j -> s
    Var(i), Ok(Unbound(level)), other, _ | other, _, Var(i), Ok(Unbound(level)) -> {
      // TODO OCCURS CHECK
      State(..s, bindings: dict.insert(s.bindings, i, Bound(other)))
    }
    Fun(arg1, eff1, ret1), _, Fun(arg2, eff2, ret2), _ -> {
      let s = unify(arg1, arg2, s)
      let s = unify(eff1, eff2, s)
      let s = unify(ret1, ret2, s)
      s
    }
    Integer, _, Integer, _ -> s
    Binary, _, Binary, _ -> s
    String, _, String, _ -> s

    List(el1), _, List(el2), _ -> unify(el1, el2, s)
    Empty, _, Empty, _ -> s
    Record(rows1), _, Record(rows2), _ -> unify(rows1, rows2, s)
    RowExtend(l1, field1, rest1), _, other, _
    | other, _, RowExtend(l1, field1, rest1), _ -> {
      let assert Ok(#(field2, rest2, s)) = rewrite_row(l1, other, s)
      let s = unify(field1, field2, s)
      let s = unify(rest1, rest2, s)
      s
    }
    EffectExtend(l1, #(lift1, reply1), r1), _, other, _
    | other, _, EffectExtend(l1, #(lift1, reply1), r1), _ -> {
      let assert Ok(#(#(lift2, reply2), r2, s)) = rewrite_effect(l1, other, s)
      let s = unify(lift1, lift2, s)
      let s = unify(reply1, reply2, s)
      let s = unify(r1, r2, s)
      s
    }
    _, _, _, _ -> {
      io.debug(#("unifying", t1, t2))
      panic as "something"
    }
  }
}

fn rewrite_row(required, type_, s) {
  case type_ {
    Empty -> Error(Nil)
    RowExtend(l, field, rest) if l == required -> Ok(#(field, rest, s))
    RowExtend(l, other_field, rest) -> {
      let assert Ok(#(field, new_tail, s)) = rewrite_row(l, rest, s)
      let rest = RowExtend(required, other_field, new_tail)
      Ok(#(field, rest, s))
    }
    Var(i) -> {
      let #(s, field) = newvar(s)
      let #(s, rest) = newvar(s)
      let type_ = RowExtend(required, field, rest)
      let s = State(..s, bindings: dict.insert(s.bindings, i, Bound(type_)))
      Ok(#(field, rest, s))
    }
    _ -> Error(Nil)
  }
}

fn rewrite_effect(required, type_, s) {
  case type_ {
    Empty -> Error(Nil)
    EffectExtend(l, eff, rest) if l == required -> Ok(#(eff, rest, s))
    EffectExtend(l, other_eff, rest) -> {
      let assert Ok(#(eff, new_tail, s)) = rewrite_effect(l, rest, s)
      // use #(eff, new_tail, s) <-  try(rewrite_effect(l, rest, s))
      let rest = EffectExtend(required, other_eff, new_tail)
      Ok(#(eff, rest, s))
    }
    Var(i) -> {
      let #(s, lift) = newvar(s)
      let #(s, reply) = newvar(s)
      let #(s, rest) = newvar(s)
      let type_ = EffectExtend(required, #(lift, reply), rest)
      let s = State(..s, bindings: dict.insert(s.bindings, i, Bound(type_)))
      Ok(#(#(lift, reply), rest, s))
    }
    _ -> Error(Nil)
  }
}
