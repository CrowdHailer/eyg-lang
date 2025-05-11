import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/binding/unify
import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/set

pub fn new_state() {
  dict.new()
}

pub fn infer(source, eff, refs, level, bindings) {
  let source = source
  let #(bindings, _type, _eff, acc) =
    do_infer(source, [], eff, refs, level, bindings)
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

pub fn ftv(type_) {
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
    t.Promise(inner) -> ftv(inner)
  }
}

fn close(type_, level, bindings) {
  case binding.resolve(type_, bindings) {
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

pub type Env =
  List(#(String, binding.Poly))

pub fn do_infer(source, env, eff, refs: dict.Dict(_, _), level, bindings) {
  let #(exp, _meta) = source
  case exp {
    ir.Variable(x) ->
      case list.key_find(env, x) {
        Ok(scheme) -> {
          let #(type_, bindings) = binding.instantiate(scheme, level, bindings)
          let #(type_, bindings) = open(type_, level, bindings)
          let meta = #(Ok(Nil), type_, t.Empty, env)
          #(bindings, type_, eff, #(ir.Variable(x), meta))
        }
        Error(Nil) -> {
          let #(type_, bindings) = binding.mono(level, bindings)
          let meta = #(Error(error.MissingVariable(x)), type_, t.Empty, env)
          #(bindings, type_, eff, #(ir.Variable(x), meta))
        }
      }
    ir.Lambda(x, body) -> {
      let #(type_x, bindings) = binding.mono(level, bindings)
      let assert t.Var(i) = type_x
      let scheme_x = t.Var(#(False, i))
      let level = level + 1
      let #(type_eff, bindings) = binding.mono(level, bindings)

      let #(bindings, type_r, type_eff, inner) =
        do_infer(body, [#(x, scheme_x), ..env], type_eff, refs, level, bindings)

      let type_ = t.Fun(type_x, type_eff, type_r)
      let level = level - 1
      let record = close(type_, level, bindings)
      let meta = #(Ok(Nil), record, t.Empty, env)
      #(bindings, type_, eff, #(ir.Lambda(x, inner), meta))
    }
    ir.Apply(fun, arg) -> {
      // Effects are passed to inner infer because they are effect for creating evaluatin the func and arg,
      // not the effect of applying them
      let level = level + 1
      let #(bindings, ty_fun, eff, fun) =
        do_infer(fun, env, eff, refs, level, bindings)
      let #(bindings, ty_arg, eff, arg) =
        do_infer(arg, env, eff, refs, level, bindings)

      let #(ty_ret, bindings) = binding.mono(level, bindings)
      let #(test_eff, bindings) = binding.mono(level, bindings)

      let #(bindings, result) = case
        unify.unify(t.Fun(ty_arg, test_eff, ty_ret), ty_fun, level, bindings)
      {
        Ok(bindings) -> #(bindings, Ok(Nil))
        Error(reason) -> #(bindings, Error(reason))
      }

      let level = level - 1
      // At this point we just check that the effects would generalise a level up.
      // It doesn't matter if the eftects are in arg because we apply the arg here
      // so we're only interested in final effects
      let #(last, mapped) = eff_tail(binding.resolve(test_eff, bindings))
      let raised = case last {
        Error(Nil) -> test_eff
        Ok(i) -> {
          let assert Ok(binding) = dict.get(bindings, i)
          let level = level - 1
          case binding {
            binding.Unbound(l) if l > level -> {
              mapped
            }
            _ -> test_eff
          }
        }
      }

      let #(bindings, result) = case
        unify.unify(test_eff, eff, level, bindings)
      {
        Ok(bindings) -> #(bindings, result)
        // First error, is there a result.and function
        Error(reason) -> #(bindings, case result {
          Ok(Nil) -> Error(reason)
          Error(reason) -> Error(reason)
        })
      }
      let record = close(ty_ret, level, bindings)
      let meta = #(result, record, raised, env)

      // This returns the raised effect even if error
      #(bindings, ty_ret, eff, #(ir.Apply(fun, arg), meta))
    }
    ir.Let(label, value, then) -> {
      let level = level + 1
      let #(bindings, ty_value, eff, value) =
        do_infer(value, env, eff, refs, level, bindings)
      let level = level - 1
      let sch_value =
        binding.gen(close(ty_value, level, bindings), level, bindings)

      let #(bindings, ty_then, eff, then) =
        do_infer(then, [#(label, sch_value), ..env], eff, refs, level, bindings)
      let meta = #(Ok(Nil), ty_then, t.Empty, env)
      #(bindings, ty_then, eff, #(ir.Let(label, value, then), meta))
    }
    ir.Vacant -> {
      let #(type_, bindings) = binding.mono(level, bindings)
      let meta = #(Error(error.Todo), type_, t.Empty, env)
      #(bindings, type_, eff, #(ir.Vacant, meta))
    }
    ir.Integer(value) ->
      prim(t.Integer, env, eff, level, bindings, ir.Integer(value))
    ir.Binary(value) ->
      prim(t.Binary, env, eff, level, bindings, ir.Binary(value))
    ir.String(value) ->
      prim(t.String, env, eff, level, bindings, ir.String(value))
    ir.Tail -> prim(t.List(q(0)), env, eff, level, bindings, ir.Tail)
    ir.Cons -> prim(cons(), env, eff, level, bindings, ir.Cons)
    ir.Empty -> prim(t.Record(t.Empty), env, eff, level, bindings, ir.Empty)
    ir.Extend(label) ->
      prim(extend(label), env, eff, level, bindings, ir.Extend(label))
    ir.Overwrite(label) ->
      prim(overwrite(label), env, eff, level, bindings, ir.Overwrite(label))
    ir.Select(label) ->
      prim(select(label), env, eff, level, bindings, ir.Select(label))
    ir.Tag(label) -> prim(tag(label), env, eff, level, bindings, ir.Tag(label))
    ir.Case(label) ->
      prim(case_(label), env, eff, level, bindings, ir.Case(label))
    ir.NoCases -> prim(nocases(), env, eff, level, bindings, ir.NoCases)
    ir.Perform(label) ->
      prim(perform(label), env, eff, level, bindings, ir.Perform(label))
    ir.Handle(label) ->
      prim(handle(label), env, eff, level, bindings, ir.Handle(label))
    ir.Builtin(id) ->
      case builtin(id) {
        Ok(poly) -> prim(poly, env, eff, level, bindings, ir.Builtin(id))
        Error(Nil) -> {
          let #(type_, bindings) = binding.mono(level, bindings)
          let meta = #(Error(error.MissingBuiltin(id)), type_, t.Empty, env)
          #(bindings, type_, eff, #(ir.Builtin(id), meta))
        }
      }
    ir.Reference(cid) ->
      lookup_ref(
        refs,
        error.MissingReference(cid),
        cid,
        env,
        eff,
        level,
        bindings,
      )
    ir.Release(package, release, cid) ->
      lookup_ref(
        refs,
        error.UndefinedRelease(package, release, cid),
        cid,
        env,
        eff,
        level,
        bindings,
      )
  }
}

fn lookup_ref(refs, reason, id, env, eff, level, bindings) {
  case dict.get(refs, id) {
    Ok(poly) -> prim(poly, env, eff, level, bindings, ir.Reference(id))
    Error(Nil) -> {
      let #(type_, bindings) = binding.mono(level, bindings)
      let meta = #(Error(reason), type_, t.Empty, env)
      #(bindings, type_, eff, #(ir.Reference(id), meta))
    }
  }
}

fn prim(scheme, env, eff, level, bindings, exp) {
  let #(type_, bindings) = binding.instantiate(scheme, level, bindings)
  let #(t, bindings) = open(type_, level, bindings)
  let meta = #(Ok(Nil), type_, t.Empty, env)
  #(bindings, t, eff, #(exp, meta))
}

fn pure1(arg1, ret) {
  t.Fun(arg1, t.Empty, ret)
}

fn pure2(arg1, arg2, ret) {
  t.Fun(arg1, t.Empty, t.Fun(arg2, t.Empty, ret))
}

fn pure3(arg1, arg2, arg3, ret) {
  t.Fun(arg1, t.Empty, t.Fun(arg2, t.Empty, t.Fun(arg3, t.Empty, ret)))
}

// q for quantified
pub fn q(i) {
  t.Var(#(True, i))
}

fn cons() {
  pure2(q(0), t.List(q(0)), t.List(q(0)))
}

fn extend(l) {
  pure2(q(0), t.Record(q(1)), t.Record(t.RowExtend(l, q(0), q(1))))
}

fn overwrite(l) {
  pure2(
    q(0),
    t.Record(t.RowExtend(l, q(1), q(2))),
    t.Record(t.RowExtend(l, q(0), q(2))),
  )
}

fn select(l) {
  pure1(t.Record(t.RowExtend(l, q(0), q(1))), q(0))
}

fn tag(l) {
  pure1(q(0), t.Union(t.RowExtend(l, q(0), q(1))))
}

pub fn case_(label) {
  let inner = q(0)
  let eff = q(1)
  let return = q(2)
  let tail = q(3)
  let input = t.Union(t.RowExtend(label, inner, tail))
  let branch = t.Fun(inner, eff, return)
  let otherwise = t.Fun(t.Union(tail), eff, return)
  let exec = t.Fun(input, eff, return)
  pure2(branch, otherwise, exec)
}

pub fn nocases() {
  pure1(t.Union(t.Empty), q(0))
}

fn perform(l) {
  t.Fun(q(0), t.EffectExtend(l, #(q(0), q(1)), t.Empty), q(1))
}

pub fn handle(label) {
  let lift = q(0)
  let reply = q(1)
  let tail = q(2)
  let return = q(3)
  let kont = t.Fun(reply, tail, return)
  let handler = t.Fun(lift, t.Empty, t.Fun(kont, tail, return))

  let exec =
    t.Fun(
      t.Record(t.Empty),
      t.EffectExtend(label, #(lift, reply), tail),
      return,
    )
  t.Fun(handler, t.Empty, t.Fun(exec, tail, return))
}

// equal fn should be open in fn that takes boolean and other union
fn builtin(name) {
  list.key_find(builtins(), name)
}

pub fn builtins() {
  [
    #("equal", pure2(q(0), q(0), t.boolean)),
    // debug is an effect because the format is not fully specified
    // #("debug", pure1(q(0), t.String)),

    // if the passed in constructor raises an effect then fix does too
    #("fix", t.Fun(t.Fun(q(0), q(1), q(0)), q(1), q(0))),
    // Eval is effectful and so should be an effect, does that mean that Serialize also needs to be an effect
    // #(
    //   "eval",
    //   t.Fun(q(0), t.EffectExtend("Eval", #(t.unit, t.unit), t.Empty), q(1)),
    // ),

    // #("serialize", pure1(q(0), t.String)),
    // #("capture", pure1(q(0), t.ast())),

    // An effect or something that is built in EYG itself
    // #("to_javascript", pure2(q(0), q(1), t.String)),

    // These should be in EYG or effects if needed
    // #("encode_uri", pure1(t.String, t.String)),
    // #("decode_uri_component", pure1(t.String, t.String)),
    // #("base64_encode", pure1(t.Binary, t.String)),

    #("int_compare", {
      let return = t.union([#("Lt", t.unit), #("Eq", t.unit), #("Gt", t.unit)])
      pure2(t.Integer, t.Integer, return)
    }),
    #("int_add", pure2(t.Integer, t.Integer, t.Integer)),
    #("int_subtract", pure2(t.Integer, t.Integer, t.Integer)),
    #("int_multiply", pure2(t.Integer, t.Integer, t.Integer)),
    #("int_divide", pure2(t.Integer, t.Integer, t.result(t.Integer, t.unit))),
    #("int_absolute", pure1(t.Integer, t.Integer)),
    // Removed as negate is subtract(0, x) or multiply(-1, x)
    // #("int_negate", pure1(t.Integer, t.Integer)),

    #("int_parse", pure1(t.String, t.result(t.Integer, t.unit))),
    #("int_to_string", pure1(t.Integer, t.String)),
    // string
    #("string_append", pure2(t.String, t.String, t.String)),
    #("string_split", {
      let return = t.record([#("head", t.String), #("tail", t.List(t.String))])
      pure2(t.String, t.String, return)
    }),
    #("string_split_once", {
      let return = t.record([#("head", t.String), #("tail", t.String)])
      pure2(t.String, t.String, t.result(return, t.unit))
    }),
    #("string_replace", pure3(t.String, t.String, t.String, t.String)),
    #("string_uppercase", pure1(t.String, t.String)),
    #("string_lowercase", pure1(t.String, t.String)),
    // pop prefix only works for start with. I'm not sure pop prefix is the format we want to stay with
    #("string_starts_with", pure2(t.String, t.String, t.boolean)),
    #("string_ends_with", pure2(t.String, t.String, t.boolean)),
    #("string_length", pure1(t.String, t.Integer)),
    // #("pop_grapheme", {
    //   let return = t.record([#("head", t.String), #("tail", t.String)])
    //   pure1(t.String, t.result(return, t.unit))
    // }),
    // #("pop_prefix", {
    //   let eff = q(0)
    //   let return = q(1)
    //   let yes = t.Fun(t.String, eff, return)
    //   let no = t.Fun(t.unit, eff, return)
    //   t.Fun(
    //     t.String,
    //     t.Empty,
    //     t.Fun(t.String, t.Empty, t.Fun(yes, t.Empty, t.Fun(no, eff, return))),
    //   )
    // }),
    #("string_to_binary", pure1(t.String, t.Binary)),
    #("string_from_binary", pure1(t.Binary, t.result(t.String, t.unit))),
    // This should be literals
    #("binary_from_integers", pure1(t.List(t.Integer), t.Binary)),
    #("binary_fold", {
      let acc = q(1)
      // eff only thrown by reduce when last argument given
      let eff = q(2)
      let reducer = t.Fun(t.Integer, eff, t.Fun(acc, eff, acc))
      pure2(t.Binary, acc, t.Fun(reducer, eff, acc))
    }),
    // Don't optimise for object creation
    // #("uncons", {
    //   let el = q(0)
    //   let eff = q(1)
    //   let return = q(2)
    //   let empty = t.Fun(t.unit, eff, return)
    //   let nonempty = t.Fun(el, eff, t.Fun(t.List(el), eff, return))
    //   t.Fun(
    //     t.List(el),
    //     t.Empty,
    //     t.Fun(empty, t.Empty, t.Fun(nonempty, eff, return)),
    //   )
    // }),
    #("list_pop", {
      let return = t.record([#("head", q(0)), #("tail", t.List(q(0)))])
      pure1(t.List(q(0)), t.result(return, t.unit))
    }),
    #("list_fold", {
      let el = q(0)
      let acc = q(1)
      // eff only thrown by reduce when last argument given
      let eff = q(2)
      let reducer = t.Fun(el, eff, t.Fun(acc, eff, acc))
      pure2(t.List(el), acc, t.Fun(reducer, eff, acc))
    }),
  ]
}
