// you can't open close in unification because will loose need for limited effects
// if you close for env you need to open at var
// closing doesn't work to slim down list of functions, theres a con contra thing here
// maybe when printing we can see what happens
// schema is not useful because in cases when unknown f is called (f) -> { f(x) } when using schema
// you lose all relation between what you see for f and f(x)
// this does mean things that are obvious i.e. (x) -> {x} end up will all extra ancilory info
// in essence you are looking at type of hole and not mininmal type fo thing
// could save both
// Let's are very ugly because is final expression return

// schema for looking in type for looking out
// We can close type_ after looking internally becuase the information is not useful where as for effect fields they still get added
// Can't close if type is in env
// Can only close if would also generalise
// Do one level higher

// Testing such that the env has no effects drives the effects of fns being empty not that we can ignore them
// well we can but only by getting more info lost with generalising

// In apply doing only close means that types keep unifying for the lift and lower types
// Show typing example where an error use of a return type leaves it as e but if fixed it gets found properly

// TODO some tests with fn capture
// let x
// let f = (_) -> { x }

// TODO do types in a webpage
// source, tree, types
// highlight each case where and effect is created do lines from selection to the correct part of the tree
// do not wrap unless hovering on the types

// try and write the algorithm in eyg
// potentially try the interpreter

// TODO rename level_j
import gleam/dict.{type Dict}
import gleam/io
import gleam/int
import gleam/list
import gleam/result.{try}
import gleam/set
import eygir/expression as e

pub type Reason {
  MissingVariable(String)
  TypeMismatch(Type(Int), Type(Int))
  MissingRow(String)
}

pub type Type(var) {
  Var(key: var)
  Fun(Type(var), Type(var), Type(var))
  Binary
  Integer
  String
  List(Type(var))
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

pub type State {
  State(current_typevar: Int, current_level: Int, bindings: Dict(Int, Binding))
}

pub fn new_state() {
  State(0, 1, dict.new())
}

pub fn infer(source, eff, state) {
  let #(state, _type, _eff, acc) = do_infer(source, [], eff, state)
  #(acc, state)
}

fn new(state: State, v) {
  let State(tvar, level, bindings) = state
  let t = v(tvar)
  let bindings = dict.insert(bindings, tvar, Unbound(level))
  let tvar = tvar + 1
  let state = State(tvar, level, bindings)
  #(state, t)
}

pub fn newvar(state) {
  new(state, Var)
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
          // case i < l {
          //   False -> Nil
          //   True -> panic as "oooh"
          // }
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
    List(el) -> List(gen(el, s))
    Record(rows) -> Record(gen(rows, s))
    Union(rows) -> Union(gen(rows, s))
    RowExtend(label, field, rest) -> {
      let field = gen(field, s)
      let rest = gen(rest, s)
      RowExtend(label, field, rest)
    }
    EffectExtend(label, #(lift, reply), rest) -> {
      let lift = gen(lift, s)
      let reply = gen(reply, s)
      let rest = gen(rest, s)
      EffectExtend(label, #(lift, reply), rest)
    }
  }
}

pub fn instantiate(poly, state) {
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
    List(el) -> {
      let #(el, subst, state) = do_instantiate(el, subst, state)
      #(List(el), subst, state)
    }
    Record(rows) -> {
      let #(rows, subst, state) = do_instantiate(rows, subst, state)
      #(Record(rows), subst, state)
    }
    Union(rows) -> {
      let #(rows, subst, state) = do_instantiate(rows, subst, state)
      #(Union(rows), subst, state)
    }
    RowExtend(label, field, rest) -> {
      let #(field, subst, state) = do_instantiate(field, subst, state)
      let #(rest, subst, state) = do_instantiate(rest, subst, state)
      #(RowExtend(label, field, rest), subst, state)
    }
    EffectExtend(label, #(lift, reply), rest) -> {
      let #(lift, subst, state) = do_instantiate(lift, subst, state)
      let #(reply, subst, state) = do_instantiate(reply, subst, state)
      let #(rest, subst, state) = do_instantiate(rest, subst, state)
      #(EffectExtend(label, #(lift, reply), rest), subst, state)
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

fn ftv(type_) {
  case type_ {
    Var(x) -> set.from_list([x])
    Fun(arg, eff, ret) -> set.union(ftv(arg), set.union(ftv(eff), ftv(ret)))
    Integer | Binary | String -> set.new()
    List(el) -> ftv(el)
    Record(rows) -> ftv(rows)
    Union(inner) -> ftv(inner)
    Empty -> set.new()
    RowExtend(_, field, tail) -> set.union(ftv(field), ftv(tail))
    EffectExtend(_, #(lift, reply), tail) ->
      set.union(ftv(lift), set.union(ftv(reply), ftv(tail)))
  }
}

// TODO move to levels
fn close(type_, s: State) {
  case resolve(type_, s.bindings) {
    Fun(arg, eff, ret) -> {
      let eff = close_eff(arg, eff, ret, s)
      Fun(arg, eff, close(ret, s))
    }
    _ -> type_
  }
}

fn close_eff(arg, eff, ret, s: State) {
  let #(last, mapped) = eff_tail(eff)
  case last {
    Ok(i) -> {
      // //  can only close if would also generalise
      let assert Ok(Unbound(l)) = dict.get(s.bindings, i)
      // io.debug(#(l, s.current_level))
      //   case  {
      //      -> 
      //   }
      case
        !set.contains(set.union(ftv(arg), ftv(ret)), i)
        && l > s.current_level
      {
        True -> mapped
        False -> eff
      }
    }
    Error(Nil) -> eff
  }
}

fn eff_tail(eff) {
  case eff {
    Var(x) -> #(Ok(x), Empty)
    EffectExtend(l, f, tail) -> {
      let #(result, tail) = eff_tail(tail)
      #(result, EffectExtend(l, f, tail))
    }
    _ -> #(Error(Nil), eff)
  }
}

// Dont try and be cleever with putting on acc as
// really large effect envs still often put nothin on the acc
fn do_infer(source, env, eff, s) {
  case source {
    e.Variable(x) ->
      case list.key_find(env, x) {
        Ok(scheme) -> {
          // io.debug(scheme)
          let #(s, type_) = instantiate(scheme, s)
          let #(s, type_) = open(type_, s)
          // io.debug(type_)
          #(s, type_, eff, [#(Ok(Nil), type_, Empty, env)])
        }

        Error(Nil) -> {
          let #(s, type_) = newvar(s)
          #(s, type_, eff, [#(Error(MissingVariable(x)), type_, Empty, env)])
        }
      }
    e.Lambda(x, body) -> {
      let #(s, type_x) = newvar(s)
      let s = enter_level(s)
      let #(s, type_eff) = newvar(s)

      let #(s, type_r, type_eff, inner) =
        do_infer(body, [#(x, dont(type_x)), ..env], type_eff, s)

      let type_ = Fun(type_x, type_eff, type_r)
      let s = exit_level(s)
      let record = close(type_, s)
      #(s, type_, eff, [#(Ok(Nil), record, Empty, env), ..inner])
    }
    e.Apply(fun, arg) -> {
      // I think these effects ar passed through because they are for creating the fn not calling it
      let #(s, ty_fun, eff, inner_fun) = do_infer(fun, env, eff, s)
      let #(s, ty_arg, eff, inner_arg) = do_infer(arg, env, eff, s)
      let inner = list.append(inner_fun, inner_arg)

      let #(s, ty_ret) = newvar(s)
      let #(s, test_eff) = newvar(s)

      let #(s, result) = case unify(Fun(ty_arg, test_eff, ty_ret), ty_fun, s) {
        Ok(s) -> #(s, Ok(Nil))
        Error(reason) -> #(s, Error(reason))
      }

      // Can close as if it was a let statement above, schema might be interesting
      let assert Fun(_, raised, _) = close(ty_fun, exit_level(s))

      let #(s, result) = case unify(test_eff, eff, s) {
        Ok(s) -> #(s, result)
        // First error, is there a result.and function
        Error(reason) -> #(s, case result {
          Ok(Nil) -> Error(reason)
          Error(reason) -> Error(reason)
        })
      }

      // This returns the raised effect even if error
      #(s, ty_ret, eff, [#(result, ty_ret, raised, env), ..inner])
    }
    // This has two places that create effects but in the acc I don't want any effects
    e.Let(label, value, then) -> {
      let s = enter_level(s)
      let #(s, ty_value, eff, inner_value) = do_infer(value, env, eff, s)
      let s = exit_level(s)
      let sch_value = gen(close(ty_value, s), s)

      let #(s, ty_then, eff, inner_then) =
        do_infer(then, [#(label, sch_value), ..env], eff, s)
      let inner = list.append(inner_value, inner_then)
      #(s, ty_then, eff, [#(Ok(Nil), ty_then, Empty, env), ..inner])
    }
    e.Integer(_) -> #(s, Integer, eff, [#(Ok(Nil), Integer, Empty, env)])
    e.Binary(_) -> #(s, String, eff, [#(Ok(Nil), Binary, Empty, env)])
    e.Str(_) -> #(s, String, eff, [#(Ok(Nil), String, Empty, env)])
    e.Tail -> {
      let #(s, el) = newvar(s)
      #(s, List(el), eff, [#(Ok(Nil), List(el), Empty, env)])
    }

    e.Cons -> {
      let #(s, el) = newvar(s)
      let list = List(el)
      let type_ = pure2(el, list, list)
      #(s, type_, eff, [#(Ok(Nil), type_, Empty, env)])
      // TODO move to primitive
    }
    e.Empty -> #(s, Record(Empty), eff, [#(Ok(Nil), Record(Empty), Empty, env)])
    e.Extend(label) -> {
      let #(s, field) = newvar(s)
      let #(s, rest) = newvar(s)
      let type_ =
        pure2(field, Record(rest), Record(RowExtend(label, field, rest)))
      #(s, type_, eff, [#(Ok(Nil), type_, Empty, env)])
    }
    e.Select(label) -> {
      let #(s, field) = newvar(s)
      let #(s, rest) = newvar(s)
      let type_ = pure1(Record(RowExtend(label, field, rest)), field)
      #(s, type_, eff, [#(Ok(Nil), type_, Empty, env)])
    }
    e.Tag(label) -> {
      let #(s, inner) = newvar(s)
      let #(s, rest) = newvar(s)
      let type_ = pure1(inner, Union(RowExtend(label, inner, rest)))
      #(s, type_, eff, [#(Ok(Nil), type_, Empty, env)])
    }
    e.Perform(label) -> {
      // define it closed because will be opend
      let scheme =
        Fun(
          Var(#(True, 0)),
          EffectExtend(label, #(Var(#(True, 0)), Var(#(True, 1))), Empty),
          Var(#(True, 1)),
        )
      let #(s, type_) = instantiate(scheme, s)
      let #(s, t) = open(type_, s)
      #(s, t, eff, [#(Ok(Nil), type_, Empty, env)])
    }
    e.Builtin(label) -> {
      let result = primitive(label)
      let #(result, s, type_) = case result {
        Ok(type_) -> #(Ok(Nil), s, type_)
        Error(reason) -> {
          let #(s, type_) = newvar(s)
          #(Error(reason), s, type_)
        }
      }
      #(s, type_, eff, [#(result, type_, Empty, env)])
    }
    _ -> {
      io.debug(source)
      panic as "unspeorted"
    }
  }
}

// const extend = 

fn pure1(arg1, ret) {
  Fun(arg1, Empty, ret)
}

fn pure2(arg1, arg2, ret) {
  Fun(arg1, Empty, Fun(arg2, Empty, ret))
}

fn primitive(name) {
  case name {
    "integer_add" -> Ok(pure2(Integer, Integer, Integer))
    _ -> Error(MissingVariable(name))
  }
}

pub fn resolve(type_, bindings) {
  case type_ {
    Var(i) -> {
      // TODO minus numbers might get
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
    Binary -> Binary
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
  }
}

fn find(type_, s: State) {
  case type_ {
    Var(i) -> dict.get(s.bindings, i)
    _other -> Error(Nil)
  }
}

fn occurs_and_levels(i, level, type_, s: State) {
  case type_ {
    Var(j) if i == j -> panic as "recursive"
    Var(j) -> {
      let assert Ok(binding) = dict.get(s.bindings, j)
      case binding {
        Unbound(l) -> {
          let l = int.min(l, level)
          let bindings = dict.insert(s.bindings, j, Unbound(l))
          State(..s, bindings: bindings)
        }
        Bound(type_) -> occurs_and_levels(i, level, type_, s)
      }
    }
    Fun(arg, eff, ret) -> {
      let s = occurs_and_levels(i, level, arg, s)
      let s = occurs_and_levels(i, level, eff, s)
      let s = occurs_and_levels(i, level, ret, s)
      s
    }
    Integer -> s
    Binary -> s
    String -> s
    List(el) -> occurs_and_levels(i, level, el, s)
    Record(row) -> occurs_and_levels(i, level, row, s)
    Union(row) -> occurs_and_levels(i, level, row, s)
    Empty -> s
    RowExtend(_, field, rest) -> {
      let s = occurs_and_levels(i, level, field, s)
      let s = occurs_and_levels(i, level, rest, s)
      s
    }
    EffectExtend(_, #(lift, reply), rest) -> {
      let s = occurs_and_levels(i, level, lift, s)
      let s = occurs_and_levels(i, level, reply, s)
      let s = occurs_and_levels(i, level, rest, s)
      s
    }
  }
}

fn unify(t1, t2, s: State) {
  case t1, find(t1, s), t2, find(t2, s) {
    _, Ok(Bound(t1)), _, _ -> unify(t1, t2, s)
    _, _, _, Ok(Bound(t2)) -> unify(t1, t2, s)
    Var(i), _, Var(j), _ if i == j -> Ok(s)
    Var(i), Ok(Unbound(level)), other, _ | other, _, Var(i), Ok(Unbound(level)) -> {
      let s = occurs_and_levels(i, level, other, s)
      // io.debug(#(level, other, find(other, s)))
      // TODO OCCURS CHECK
      Ok(State(..s, bindings: dict.insert(s.bindings, i, Bound(other))))
    }
    Fun(arg1, eff1, ret1), _, Fun(arg2, eff2, ret2), _ -> {
      use s <- try(unify(arg1, arg2, s))
      use s <- try(unify(eff1, eff2, s))
      unify(ret1, ret2, s)
    }
    Integer, _, Integer, _ -> Ok(s)
    Binary, _, Binary, _ -> Ok(s)
    String, _, String, _ -> Ok(s)

    List(el1), _, List(el2), _ -> unify(el1, el2, s)
    Empty, _, Empty, _ -> Ok(s)
    Record(rows1), _, Record(rows2), _ -> unify(rows1, rows2, s)
    Union(rows1), _, Union(rows2), _ -> unify(rows1, rows2, s)
    RowExtend(l1, field1, rest1), _, other, _
    | other, _, RowExtend(l1, field1, rest1), _ -> {
      use #(field2, rest2, s) <- try(rewrite_row(l1, other, s))
      use s <- try(unify(field1, field2, s))
      unify(rest1, rest2, s)
    }
    EffectExtend(l1, #(lift1, reply1), r1), _, other, _
    | other, _, EffectExtend(l1, #(lift1, reply1), r1), _ -> {
      use #(#(lift2, reply2), r2, s) <- try(rewrite_effect(l1, other, s))
      use s <- try(unify(lift1, lift2, s))
      use s <- try(unify(reply1, reply2, s))
      unify(r1, r2, s)
    }
    _, _, _, _ -> Error(TypeMismatch(t1, t2))
  }
}

fn rewrite_row(required, type_, s) {
  case type_ {
    Empty -> Error(MissingRow(required))
    RowExtend(l, field, rest) if l == required -> Ok(#(field, rest, s))
    RowExtend(l, other_field, rest) -> {
      use #(field, new_tail, s) <- try(rewrite_row(l, rest, s))
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
    // _ -> Error(TypeMismatch(RowExtend(required, type_, Empty), type_))
    _ -> panic as "bad row"
  }
}

fn rewrite_effect(required, type_, s: State) {
  case type_ {
    Empty -> Error(MissingRow(required))
    EffectExtend(l, eff, rest) if l == required -> Ok(#(eff, rest, s))
    EffectExtend(l, other_eff, rest) -> {
      use #(eff, new_tail, s) <- try(rewrite_effect(required, rest, s))
      // use #(eff, new_tail, s) <-  try(rewrite_effect(l, rest, s))
      let rest = EffectExtend(l, other_eff, new_tail)
      Ok(#(eff, rest, s))
    }
    Var(i) -> {
      let #(s, lift) = newvar(s)
      let #(s, reply) = newvar(s)

      let assert Ok(Unbound(level)) = dict.get(s.bindings, i)
      // let #(s, rest) = newvar(s)
      let State(tvar, level, bindings) = s
      let rest = Var(tvar)
      let bindings = dict.insert(bindings, tvar, Unbound(level))
      let tvar = tvar + 1
      let s = State(tvar, level, bindings)
      // #(s, t)

      let type_ = EffectExtend(required, #(lift, reply), rest)
      let s = State(..s, bindings: dict.insert(s.bindings, i, Bound(type_)))
      Ok(#(#(lift, reply), rest, s))
    }
    // _ -> Error(TypeMismatch(EffectExtend(required, type_, Empty), type_))
    _ -> panic as "bad effect"
  }
}
