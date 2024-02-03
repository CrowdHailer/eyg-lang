import gleam/dict.{type Dict}
import gleam/io
import gleam/int
import gleam/list
import gleam/string
import eygir/expression as e

pub type Type(var) {
  Var(key: var)
  Fun(Type(var), Type(var), Type(var))
  Binary
  Integer
  String
  LinkedList(Type(var))
  // Types Record/Union must be Empty/Extend/Var
  Record(Type(var))
  Union(Type(var))
  Empty
  RowExtend(String, Type(var), Type(var))
  EffectExtend(String, #(Type(var), Type(var)), Type(var))
}

pub fn render_type(typ) {
  case typ {
    Var(i) -> int.to_string(i)
    Integer -> "Integer"
    String -> "String"
    LinkedList(el) -> string.concat(["List(", render_type(el), ")"])
    Fun(from, effects, to) ->
      string.concat([
        "(",
        render_type(from),
        ") -> ",
        render_effects(effects),
        " ",
        render_type(to),
      ])
    Union(row) ->
      string.concat([
        "[",
        string.concat(
          render_row(row)
          |> list.intersperse(" | "),
        ),
        "]",
      ])
    Record(row) ->
      string.concat([
        "{",
        string.concat(
          render_row(row)
          |> list.intersperse(", "),
        ),
        "}",
      ])
    // Rows can be rendered as any mismatch in errors
    EffectExtend(_, _, _) -> string.concat(["<", render_effects(typ), ">"])
    row -> {
      string.concat([
        "{",
        render_row(row)
        |> string.join(""),
        "}",
      ])
    }
  }
}

fn render_row(r) -> List(String) {
  case r {
    Empty -> []
    Var(i) -> [string.append("..", int.to_string(i))]
    RowExtend(label, value, tail) -> {
      let field = string.concat([label, ": ", render_type(value)])
      [field, ..render_row(tail)]
    }
    _ -> ["not a valid row"]
  }
}

pub fn render_effects(effects) {
  case effects {
    Var(i) -> string.concat(["<..", int.to_string(i), ">"])
    Empty -> "<>"
    EffectExtend(label, #(lift, resume), tail) ->
      string.concat([
        "<",
        string.join(
          collect_effect(tail, [render_effect(label, lift, resume)])
          |> list.reverse,
          ", ",
        ),
        ">",
      ])
    _ -> "not a valid effect"
  }
}

fn render_effect(label, lift, resume) {
  string.concat([label, "(", render_type(lift), ", ", render_type(resume), ")"])
}

fn collect_effect(eff, acc) {
  case eff {
    EffectExtend(label, #(lift, resume), tail) ->
      collect_effect(tail, [render_effect(label, lift, resume), ..acc])
    Var(i) -> [string.append("..", int.to_string(i)), ..acc]
    Empty -> acc
    _ -> {
      io.debug("unexpected effect")
      acc
    }
  }
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
          #(s, type_, Empty, [#(Error(Nil), Empty, env)])
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
    e.Str(_) -> #(s, String, Empty, [#(Ok(String), Empty, env)])
    e.Perform(label) -> {
      let #(s, arg) = newvar(s)
      // Do this one level lower, but Do row rewriting
      let #(s, rest) = newvar(s)
      let #(s, ret) = newvar(s)
      let type_ = Fun(arg, EffectExtend(label, #(arg, ret), rest), ret)
      #(s, type_, Empty, [#(Ok(type_), Empty, env)])
    }
    _ -> {
      io.debug(source)
      panic as "unspeorted"
    }
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
    // TODO if they are the same
    _, Ok(Bound(t1)), _, _ -> unify(t1, t2, s)
    _, _, _, Ok(Bound(t2)) -> unify(t1, t2, s)
    Var(i), Ok(Unbound(level)), other, _ | other, _, Var(i), Ok(Unbound(level)) -> {
      // TODO OCCURS CHECK
      let bindings = dict.insert(s.bindings, i, Bound(other))
      State(..s, bindings: bindings)
    }
    Fun(arg1, eff1, ret1), _, Fun(arg2, eff2, ret2), _ -> {
      let s = unify(arg1, arg2, s)
      let s = unify(eff1, eff2, s)
      let s = unify(ret1, ret2, s)
    }
    Empty, _, Empty, _ -> s
    _, _, _, _ -> {
      io.debug(#("unifying", t1, t2))
      panic as "something"
    }
  }
}
