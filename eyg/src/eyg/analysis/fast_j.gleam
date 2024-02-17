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

// Fast js is good for not exploring the whole environment. Maybe that is all it is good for
// and passing abound a map of bindings is most sensible

// TODO compiling live eval in textual
import gleam/dict.{type Dict}
import gleam/io
import gleam/int
import gleam/list
import gleam/result.{try}
import gleam/set
import eygir/expression as e
import eyg/analysis/type_/isomorphic as t
import eyg/analysis/type_/binding

pub type Reason {
  MissingVariable(String)
  TypeMismatch(binding.Mono, binding.Mono)
  MissingRow(String)
}

pub fn new_state() {
  dict.new()
}

pub fn infer(source, eff, level, bindings) {
  let #(bindings, _type, _eff, acc) = do_infer(source, [], eff, level, bindings)
  #(acc, bindings)
}

fn open_effect(eff, level, bindings) {
  case eff {
    t.Empty -> binding.mono(level, bindings)
    t.EffectExtend(label, type_, eff) -> {
      let #(eff, bindings) = open_effect(eff, level, bindings)
      #(t.EffectExtend(label, type_, eff), bindings)
    }
    other -> #(other, bindings)
  }
}

fn open(type_, level, bindings) {
  case type_ {
    t.Fun(args, eff, ret) -> {
      let #(eff, bindings) = open_effect(eff, level, bindings)
      let #(ret, bindings) = open(ret, level, bindings)
      #(t.Fun(args, eff, ret), bindings)
    }
    other -> #(other, bindings)
  }
}

fn ftv(type_) {
  case type_ {
    t.Var(x) -> set.from_list([x])
    t.Fun(arg, eff, ret) -> set.union(ftv(arg), set.union(ftv(eff), ftv(ret)))
    t.Integer | t.Binary | t.String -> set.new()
    t.List(el) -> ftv(el)
    t.Record(rows) -> ftv(rows)
    t.Union(inner) -> ftv(inner)
    t.Empty -> set.new()
    t.RowExtend(_, field, tail) -> set.union(ftv(field), ftv(tail))
    t.EffectExtend(_, #(lift, reply), tail) ->
      set.union(ftv(lift), set.union(ftv(reply), ftv(tail)))
  }
}

// TODO move to levels
fn close(type_, level, bindings) {
  case resolve(type_, bindings) {
    t.Fun(arg, eff, ret) -> {
      let eff = close_eff(arg, eff, ret, level, bindings)
      t.Fun(arg, eff, close(ret, level, bindings))
    }
    _ -> type_
  }
}

fn close_eff(arg, eff, ret, level, bindings) {
  let #(last, mapped) = eff_tail(eff)
  case last {
    Ok(i) -> {
      //  can only close if would also generalise
      let assert Ok(binding.Unbound(l)) = dict.get(bindings, i)
      case !set.contains(set.union(ftv(arg), ftv(ret)), i) && l > level {
        True -> mapped
        False -> eff
      }
    }
    Error(Nil) -> eff
  }
}

fn eff_tail(eff) {
  case eff {
    t.Var(x) -> #(Ok(x), t.Empty)
    t.EffectExtend(l, f, tail) -> {
      let #(result, tail) = eff_tail(tail)
      #(result, t.EffectExtend(l, f, tail))
    }
    _ -> #(Error(Nil), eff)
  }
}

// Dont try and be cleever with putting on acc as
// really large effect envs still often put nothin on the acc
fn do_infer(source, env, eff, level, bindings) {
  case source {
    e.Variable(x) ->
      case list.key_find(env, x) {
        Ok(scheme) -> {
          let #(type_, bindings) = binding.instantiate(scheme, level, bindings)
          let #(type_, bindings) = open(type_, level, bindings)
          #(bindings, type_, eff, [#(Ok(Nil), type_, t.Empty, env)])
        }
        Error(Nil) -> {
          let #(type_, bindings) = binding.mono(level, bindings)
          #(bindings, type_, eff, [
            #(Error(MissingVariable(x)), type_, t.Empty, env),
          ])
        }
      }
    e.Lambda(x, body) -> {
      let #(type_x, bindings) = binding.mono(level, bindings)
      let assert t.Var(i) = type_x
      let scheme_x = t.Var(#(False, i))
      let level = level + 1
      let #(type_eff, bindings) = binding.mono(level, bindings)

      let #(bindings, type_r, type_eff, inner) =
        do_infer(body, [#(x, scheme_x), ..env], type_eff, level, bindings)

      let type_ = t.Fun(type_x, type_eff, type_r)
      let level = level - 1
      let record = close(type_, level, bindings)
      #(bindings, type_, eff, [#(Ok(Nil), record, t.Empty, env), ..inner])
    }
    e.Apply(fun, arg) -> {
      // I think these effects ar passed through because they are for creating the fn not calling it
      let level = level + 1
      let #(bindings, ty_fun, eff, inner_fun) =
        do_infer(fun, env, eff, level, bindings)
      let #(bindings, ty_arg, eff, inner_arg) =
        do_infer(arg, env, eff, level, bindings)
      let inner = list.append(inner_fun, inner_arg)

      let #(ty_ret, bindings) = binding.mono(level, bindings)
      let #(test_eff, bindings) = binding.mono(level, bindings)

      let #(bindings, result) = case
        unify(t.Fun(ty_arg, test_eff, ty_ret), ty_fun, level, bindings)
      {
        Ok(bindings) -> #(bindings, Ok(Nil))
        Error(reason) -> #(bindings, Error(reason))
      }

      let level = level - 1
      // Can close as if it was a let statement above, schema might be interesting

      // At this point we just check that the effects would generalise a level up.
      // It doesn't matter if the eftects are in arg because we apply the arg here
      // so we're only interested in final effects
      let #(last, mapped) = eff_tail(resolve(test_eff, bindings))
      let raised = case last {
        Error(Nil) -> test_eff
        Ok(i) -> {
          let assert Ok(binding) = dict.get(bindings, i)
          let level = level - 1
          case binding {
            binding.Unbound(l) if l > level -> {
              // let s =
              //   State(..s, bindings: dict.insert(s.bindings, i, Bound(Empty)))
              // can't make this bindings because i could have meaning from elsewhere but it seems like we should be able to

              // Maybe when generalising we map to all possible instantiations might be pure everywhere
              mapped
            }
            _ -> test_eff
          }
        }
      }

      let #(bindings, result) = case unify(test_eff, eff, level, bindings) {
        Ok(bindings) -> #(bindings, result)
        // First error, is there a result.and function
        Error(reason) -> #(bindings, case result {
          Ok(Nil) -> Error(reason)
          Error(reason) -> Error(reason)
        })
      }

      // This returns the raised effect even if error
      #(bindings, ty_ret, eff, [#(result, ty_ret, raised, env), ..inner])
    }
    // This has two places that create effects but in the acc I don't want any effects
    e.Let(label, value, then) -> {
      let level = level + 1
      let #(bindings, ty_value, eff, inner_value) =
        do_infer(value, env, eff, level, bindings)
      let level = level - 1
      let sch_value =
        binding.gen(close(ty_value, level, bindings), level, bindings)

      let #(bindings, ty_then, eff, inner_then) =
        do_infer(then, [#(label, sch_value), ..env], eff, level, bindings)
      let inner = list.append(inner_value, inner_then)
      #(bindings, ty_then, eff, [#(Ok(Nil), ty_then, t.Empty, env), ..inner])
    }
    e.Integer(_) -> #(bindings, t.Integer, eff, [
      #(Ok(Nil), t.Integer, t.Empty, env),
    ])
    e.Binary(_) -> #(bindings, t.Binary, eff, [
      #(Ok(Nil), t.Binary, t.Empty, env),
    ])
    e.Str(_) -> #(bindings, t.String, eff, [#(Ok(Nil), t.String, t.Empty, env)])

    e.Tail -> {
      let #(el, bindings) = binding.mono(level, bindings)
      #(bindings, t.List(el), eff, [#(Ok(Nil), t.List(el), t.Empty, env)])
    }
    e.Cons -> {
      let #(el, bindings) = binding.mono(level, bindings)
      let list = t.List(el)
      let type_ = pure2(el, list, list)
      #(bindings, type_, eff, [#(Ok(Nil), type_, t.Empty, env)])
      // TODO move to primitive
    }
    e.Empty -> #(bindings, t.Record(t.Empty), eff, [
      #(Ok(Nil), t.Record(t.Empty), t.Empty, env),
    ])
    e.Extend(label) -> {
      let #(field, bindings) = binding.mono(level, bindings)
      let #(rest, bindings) = binding.mono(level, bindings)
      let type_ =
        pure2(field, t.Record(rest), t.Record(t.RowExtend(label, field, rest)))
      #(bindings, type_, eff, [#(Ok(Nil), type_, t.Empty, env)])
    }
    // e.Overwrite(label) -> {
    //   // If generating with indexes maybe it's easier to just newvar with state
    //   let new = Var(#(True, 0))
    //   let old = Var(#(True, 1))
    //   let rest = Var(#(True, 2))
    //   let #(s, type_) =
    //     rename_primitive(
    //       pure2(
    //         new,
    //         Record(RowExtend(label, old, rest)),
    //         Record(RowExtend(label, new, rest)),
    //       ),
    //       s,
    //     )
    //   #(s, type_, eff, [#(Ok(Nil), type_, t.Empty, env)])
    // }
    e.Select(label) -> {
      let #(field, bindings) = binding.mono(level, bindings)
      let #(rest, bindings) = binding.mono(level, bindings)
      let type_ = pure1(t.Record(t.RowExtend(label, field, rest)), field)
      #(bindings, type_, eff, [#(Ok(Nil), type_, t.Empty, env)])
    }
    e.Tag(label) -> {
      let #(inner, bindings) = binding.mono(level, bindings)
      let #(rest, bindings) = binding.mono(level, bindings)
      let type_ = pure1(inner, t.Union(t.RowExtend(label, inner, rest)))
      #(bindings, type_, eff, [#(Ok(Nil), type_, t.Empty, env)])
    }
    e.Perform(label) -> {
      // define it closed because will be opend
      let scheme =
        t.Fun(
          t.Var(#(True, 0)),
          t.EffectExtend(
            label,
            #(t.Var(#(True, 0)), t.Var(#(True, 1))),
            t.Empty,
          ),
          t.Var(#(True, 1)),
        )
      let #(type_, bindings) = binding.instantiate(scheme, level, bindings)
      let #(t, bindings) = open(type_, level, bindings)
      #(bindings, t, eff, [#(Ok(Nil), type_, t.Empty, env)])
    }
    e.Builtin(label) -> {
      let result = primitive(label)
      let #(result, bindings, type_) = case result {
        Ok(type_) -> #(Ok(Nil), bindings, type_)
        Error(reason) -> {
          let #(type_, bindings) = binding.mono(level, bindings)
          #(Error(reason), bindings, type_)
        }
      }
      #(bindings, type_, eff, [#(result, type_, t.Empty, env)])
    }
    _ -> {
      io.debug(source)
      panic as "unspeorted"
    }
  }
}

fn rename_primitive(scheme, level, bindings) {
  binding.instantiate(scheme, level, bindings)
}

fn pure1(arg1, ret) {
  t.Fun(arg1, t.Empty, ret)
}

fn pure2(arg1, arg2, ret) {
  t.Fun(arg1, t.Empty, t.Fun(arg2, t.Empty, ret))
}

fn primitive(name) {
  case name {
    "integer_add" -> Ok(pure2(t.Integer, t.Integer, t.Integer))
    _ -> Error(MissingVariable(name))
  }
}

pub fn resolve(type_, bindings) {
  case type_ {
    t.Var(i) -> {
      // TODO minus numbers might get
      let assert Ok(binding) = dict.get(bindings, i)
      case binding {
        binding.Bound(type_) -> resolve(type_, bindings)
        _ -> type_
      }
    }
    t.Fun(arg, eff, ret) ->
      t.Fun(
        resolve(arg, bindings),
        resolve(eff, bindings),
        resolve(ret, bindings),
      )
    t.Integer -> t.Integer
    t.Binary -> t.Binary
    t.String -> t.String
    t.Empty -> t.Empty
    t.List(el) -> t.List(resolve(el, bindings))
    t.Record(rows) -> t.Record(resolve(rows, bindings))
    t.Union(rows) -> t.Union(resolve(rows, bindings))
    t.RowExtend(label, field, rest) ->
      t.RowExtend(label, resolve(field, bindings), resolve(rest, bindings))
    t.EffectExtend(label, #(lift, reply), rest) ->
      t.EffectExtend(
        label,
        #(resolve(lift, bindings), resolve(reply, bindings)),
        resolve(rest, bindings),
      )
  }
}

fn find(type_, bindings) {
  case type_ {
    t.Var(i) -> dict.get(bindings, i)
    _other -> Error(Nil)
  }
}

fn occurs_and_levels(i, level, type_, bindings) {
  case type_ {
    t.Var(j) if i == j -> panic as "recursive"
    t.Var(j) -> {
      let assert Ok(binding) = dict.get(bindings, j)
      case binding {
        binding.Unbound(l) -> {
          let l = int.min(l, level)
          let bindings = dict.insert(bindings, j, binding.Unbound(l))
          bindings
        }
        binding.Bound(type_) -> occurs_and_levels(i, level, type_, bindings)
      }
    }
    t.Fun(arg, eff, ret) -> {
      let bindings = occurs_and_levels(i, level, arg, bindings)
      let bindings = occurs_and_levels(i, level, eff, bindings)
      let bindings = occurs_and_levels(i, level, ret, bindings)
      bindings
    }
    t.Integer -> bindings
    t.Binary -> bindings
    t.String -> bindings
    t.List(el) -> occurs_and_levels(i, level, el, bindings)
    t.Record(row) -> occurs_and_levels(i, level, row, bindings)
    t.Union(row) -> occurs_and_levels(i, level, row, bindings)
    t.Empty -> bindings
    t.RowExtend(_, field, rest) -> {
      let bindings = occurs_and_levels(i, level, field, bindings)
      let bindings = occurs_and_levels(i, level, rest, bindings)
      bindings
    }
    t.EffectExtend(_, #(lift, reply), rest) -> {
      let bindings = occurs_and_levels(i, level, lift, bindings)
      let bindings = occurs_and_levels(i, level, reply, bindings)
      let bindings = occurs_and_levels(i, level, rest, bindings)
      bindings
    }
  }
}

fn unify(t1, t2, level, bindings) {
  case t1, find(t1, bindings), t2, find(t2, bindings) {
    _, Ok(binding.Bound(t1)), _, _ -> unify(t1, t2, level, bindings)
    _, _, _, Ok(binding.Bound(t2)) -> unify(t1, t2, level, bindings)
    t.Var(i), _, t.Var(j), _ if i == j -> Ok(bindings)
    t.Var(i), Ok(binding.Unbound(level)), other, _
    | other, _, t.Var(i), Ok(binding.Unbound(level)) -> {
      let bindings = occurs_and_levels(i, level, other, bindings)
      Ok(dict.insert(bindings, i, binding.Bound(other)))
    }
    t.Fun(arg1, eff1, ret1), _, t.Fun(arg2, eff2, ret2), _ -> {
      use bindings <- try(unify(arg1, arg2, level, bindings))
      use bindings <- try(unify(eff1, eff2, level, bindings))
      unify(ret1, ret2, level, bindings)
    }
    t.Integer, _, t.Integer, _ -> Ok(bindings)
    t.Binary, _, t.Binary, _ -> Ok(bindings)
    t.String, _, t.String, _ -> Ok(bindings)

    t.List(el1), _, t.List(el2), _ -> unify(el1, el2, level, bindings)
    t.Empty, _, t.Empty, _ -> Ok(bindings)
    t.Record(rows1), _, t.Record(rows2), _ ->
      unify(rows1, rows2, level, bindings)
    t.Union(rows1), _, t.Union(rows2), _ -> unify(rows1, rows2, level, bindings)
    t.RowExtend(l1, field1, rest1), _, other, _
    | other, _, t.RowExtend(l1, field1, rest1), _ -> {
      use #(field2, rest2, bindings) <- try(rewrite_row(
        l1,
        other,
        level,
        bindings,
      ))
      use bindings <- try(unify(field1, field2, level, bindings))
      unify(rest1, rest2, level, bindings)
    }
    t.EffectExtend(l1, #(lift1, reply1), r1), _, other, _
    | other, _, t.EffectExtend(l1, #(lift1, reply1), r1), _ -> {
      use #(#(lift2, reply2), r2, bindings) <- try(rewrite_effect(
        l1,
        other,
        level,
        bindings,
      ))
      use bindings <- try(unify(lift1, lift2, level, bindings))
      use bindings <- try(unify(reply1, reply2, level, bindings))
      unify(r1, r2, level, bindings)
    }
    _, _, _, _ -> Error(TypeMismatch(t1, t2))
  }
}

fn rewrite_row(required, type_, level, bindings) {
  case type_ {
    t.Empty -> Error(MissingRow(required))
    t.RowExtend(l, field, rest) if l == required -> Ok(#(field, rest, bindings))
    t.RowExtend(l, other_field, rest) -> {
      use #(field, new_tail, bindings) <- try(rewrite_row(
        l,
        rest,
        level,
        bindings,
      ))
      let rest = t.RowExtend(required, other_field, new_tail)
      Ok(#(field, rest, bindings))
    }
    t.Var(i) -> {
      let #(field, bindings) = binding.mono(level, bindings)
      let #(rest, bindings) = binding.mono(level, bindings)
      let type_ = t.RowExtend(required, field, rest)
      Ok(#(field, rest, dict.insert(bindings, i, binding.Bound(type_))))
    }
    // _ -> Error(TypeMismatch(t.RowExtend(required, type_, t.Empty), type_))
    _ -> panic as "bad row"
  }
}

fn rewrite_effect(required, type_, level, bindings) {
  case type_ {
    t.Empty -> Error(MissingRow(required))
    t.EffectExtend(l, eff, rest) if l == required -> Ok(#(eff, rest, bindings))
    t.EffectExtend(l, other_eff, rest) -> {
      use #(eff, new_tail, bindings) <- try(rewrite_effect(
        required,
        rest,
        level,
        bindings,
      ))
      // use #(eff, new_tail, s) <-  try(rewrite_effect(l, rest, s))
      let rest = t.EffectExtend(l, other_eff, new_tail)
      Ok(#(eff, rest, bindings))
    }
    t.Var(i) -> {
      let #(lift, bindings) = binding.mono(level, bindings)
      let #(reply, bindings) = binding.mono(level, bindings)

      let assert Ok(binding.Unbound(level)) = dict.get(bindings, i)
      // let #(s, rest) = newvar(s)
      // let State(tvar, level, bindings) = s
      // let rest = t.Var(tvar)
      // let bindings = dict.insert(bindings, tvar, binding.Unbound(level))
      // let tvar = tvar + 1
      // let s = State(tvar, level, bindings)
      // #(s, t)
      let #(rest, bindings) = binding.mono(level, bindings)

      let type_ = t.EffectExtend(required, #(lift, reply), rest)
      Ok(#(#(lift, reply), rest, dict.insert(bindings, i, binding.Bound(type_))))
    }
    // _ -> Error(TypeMismatch(EffectExtend(required, type_, t.Empty), type_))
    _ -> panic as "bad effect"
  }
}
