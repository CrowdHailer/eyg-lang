import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/binding/unify
import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/list
import gleam/result.{try}
import gleam/set
import multiformats/cid/v1

// None of context is tested
pub type Context {
  Context(
    env: List(#(String, binding.Poly)),
    eff: binding.Mono,
    level: Int,
    bindings: Dict(Int, binding.Binding),
  )
}

/// pure creates a new inference context to infer an expression with no effects.
/// Any effect from the expression will be a type error
pub fn pure() {
  Context([], t.Empty, 1, dict.new())
}

/// unpure creates a new inference context which accepts any effect.
pub fn unpure() {
  let bindings = dict.new()
  let #(t, bindings) = binding.mono(1, bindings)
  Context([], t, 1, bindings)
}

pub fn with_effect(context, label, lift, lower) {
  let Context(eff:, ..) = context
  let eff = t.EffectExtend(label, #(lift, lower), eff)
  Context(..context, eff:)
}

pub fn with_effects(context: Context, effects) {
  list.fold_right(effects, context, fn(context, effect) {
    let #(label, #(lift, lower)) = effect
    with_effect(context, label, lift, lower)
  })
}

pub type Analysis(meta) {
  Analysis(
    bindings: Dict(Int, binding.Binding),
    tree: ir.Node(
      #(
        Result(Nil, error.Reason),
        binding.Mono,
        binding.Mono,
        List(#(String, binding.Poly)),
      ),
    ),
    original: ir.Node(meta),
  )
}

/// Inference either finishes or asks for the type of an explicit reference.
pub type Step(a) {
  Done(a)
  Lookup(
    reference: ir.Reference,
    resume: fn(Result(binding.Poly, error.Reason)) -> Step(a),
  )
}

fn bind(step: Step(a), next: fn(a) -> Step(b)) -> Step(b) {
  case step {
    Done(value) -> next(value)
    Lookup(reference:, resume:) ->
      Lookup(reference:, resume: fn(answer) { bind(resume(answer), next) })
  }
}

/// Start checking an expression, pausing when a referenced type is needed.
pub fn check(context: Context, source: ir.Node(a)) -> Step(Analysis(a)) {
  let Context(env:, eff:, level:, bindings:) = context
  use #(bindings, _type, _eff, tree) <- bind(do_infer(
    source,
    env,
    eff,
    level,
    bindings,
  ))
  // TODO make opaque analysis
  Done(Analysis(bindings:, tree:, original: source))
}

/// Finish a check using a synchronous resolver.
pub fn resolve(
  step: Step(a),
  with resolver: fn(ir.Reference) -> Result(binding.Poly, error.Reason),
) -> a {
  case step {
    Done(value) -> value
    Lookup(reference:, resume:) ->
      resolve(resume(resolver(reference)), resolver)
  }
}

/// Finish a check with every requested reference unavailable.
pub fn unresolved(step: Step(a)) -> a {
  resolve(step, fn(reference) { Error(undefined(reference)) })
}

/// Return requested references in source order without resolving any of them.
pub fn required(step: Step(a)) -> List(ir.Reference) {
  do_required(step, [])
}

fn do_required(step, acc) {
  case step {
    Done(_) -> list.reverse(acc)
    Lookup(reference:, resume:) ->
      do_required(resume(Error(undefined(reference))), [reference, ..acc])
  }
}

/// Check using types keyed by concrete module CID.
///
/// This narrow adapter resolves only `Content` and `Pinned` references.
/// Package, version and relative references remain explicit unresolved errors;
/// callers that can resolve those forms should use `check` and `resolve`.
pub fn check_with_references(
  context: Context,
  references: Dict(v1.Cid, binding.Poly),
  source: ir.Node(a),
) -> Analysis(a) {
  check(context, source)
  |> resolve(fn(reference) {
    let found = case reference {
      ir.Content(cid) | ir.Pinned(ir.Release(_, _, cid)) ->
        dict.get(references, cid)
      ir.Package(_) | ir.Version(_, _) | ir.Relative(_) -> Error(Nil)
    }
    case found {
      Ok(poly) -> Ok(poly)
      Error(Nil) -> Error(undefined(reference))
    }
  })
}

fn undefined(reference) {
  case reference {
    ir.Content(cid) -> error.MissingReference(cid)
    ir.Package(package) -> error.UndefinedPackage(package)
    ir.Version(package, version) -> error.UndefinedVersion(package, version)
    ir.Pinned(release) -> error.UndefinedRelease(release)
    ir.Relative(location) -> error.UndefinedRelative(location)
  }
}

pub fn missing_references(inference) {
  error.missing_references(all_errors(inference))
}

pub fn all_errors(inference) {
  let Analysis(_bindings, acc, source) = inference
  let meta = ir.get_annotation(source)
  let info = ir.get_annotation(acc)
  let assert Ok(info) = list.strict_zip(meta, info)

  info
  |> list.filter_map(fn(pair) {
    let #(meta, #(result, _type, _eff, _scope)) = pair
    case result {
      Ok(Nil) -> Error(Nil)
      Error(reason) -> Ok(#(meta, reason))
    }
  })
}

fn info_at(inference: Analysis(_), desired) {
  let Analysis(_bindings, acc, source) = inference
  let meta = ir.get_annotation(source)
  let info = ir.get_annotation(acc)
  let assert Ok(info) = list.strict_zip(meta, info)
  info
  |> list.find_map(fn(pair) {
    let #(meta, info) = pair
    case meta == desired {
      True -> Ok(info)
      False -> Error(Nil)
    }
  })
}

pub fn type_at(inference: Analysis(_), desired) {
  use #(_result, type_, _effect, _scope) <- try(info_at(inference, desired))
  Ok(binding.resolve(type_, inference.bindings))
}

pub fn scope_at(inference: Analysis(_), desired) {
  use #(_result, _type, _effect, scope) <- try(info_at(inference, desired))
  Ok(scope)
}

pub fn arity_at(inference: Analysis(_), desired) {
  use type_ <- try(type_at(inference, desired))
  count_args(type_)
}

pub fn count_args(type_) {
  case type_ {
    t.Fun(_, _, return) -> Ok(do_count_args(return, 1))
    _ -> Error(Nil)
  }
}

fn do_count_args(type_, acc) {
  case type_ {
    t.Fun(_, _, return) -> do_count_args(return, acc + 1)
    _ -> acc
  }
}

/// Returns the top type from the analysis over an expression
pub fn type_(inference) {
  let Analysis(bindings, acc, _source) = inference
  let #(_tree, #(_error, type_, _eff, _env)) = acc
  binding.resolve(type_, bindings)
}

pub fn poly_type(inference) {
  let Analysis(bindings, acc, _source) = inference
  let #(_tree, #(_error, type_, _eff, _env)) = acc
  let mono = binding.resolve(type_, bindings)
  binding.gen(mono, 0, bindings)
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
    t.Never -> set.new()
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

type Env =
  List(#(String, binding.Poly))

fn do_infer(source, env, eff, level, bindings) -> Step(_) {
  let #(exp, _meta) = source
  case exp {
    ir.Variable(x) ->
      case list.key_find(env, x) {
        Ok(scheme) -> {
          let #(type_, bindings) = binding.instantiate(scheme, level, bindings)
          let #(type_, bindings) = open(type_, level, bindings)
          let meta = #(Ok(Nil), type_, t.Empty, env)
          Done(#(bindings, type_, eff, #(ir.Variable(x), meta)))
        }
        Error(Nil) -> {
          let #(type_, bindings) = binding.mono(level, bindings)
          let meta = #(Error(error.MissingVariable(x)), type_, t.Empty, env)
          Done(#(bindings, type_, eff, #(ir.Variable(x), meta)))
        }
      }
    ir.Lambda(x, body) -> {
      let #(type_x, bindings) = binding.mono(level, bindings)
      let assert t.Var(i) = type_x
      let scheme_x = t.Var(#(False, i))
      let inner_level = level + 1
      let #(type_eff, bindings) = binding.mono(inner_level, bindings)

      use #(bindings, type_r, type_eff, inner) <- bind(do_infer(
        body,
        [#(x, scheme_x), ..env],
        type_eff,
        inner_level,
        bindings,
      ))

      let type_ = t.Fun(type_x, type_eff, type_r)
      let record = close(type_, level, bindings)
      let meta = #(Ok(Nil), record, t.Empty, env)
      Done(#(bindings, type_, eff, #(ir.Lambda(x, inner), meta)))
    }
    ir.Apply(..) | ir.Let(..) -> spine(source, env, eff, level, bindings, [])
    ir.Vacant -> {
      let #(type_, bindings) = binding.mono(level, bindings)
      let meta = #(Error(error.Todo), type_, t.Empty, env)
      Done(#(bindings, type_, eff, #(ir.Vacant, meta)))
    }
    ir.Integer(value) ->
      Done(prim(t.Integer, env, eff, level, bindings, ir.Integer(value)))
    ir.Binary(value) ->
      Done(prim(t.Binary, env, eff, level, bindings, ir.Binary(value)))
    ir.String(value) ->
      Done(prim(t.String, env, eff, level, bindings, ir.String(value)))
    ir.Tail -> Done(prim(t.List(q(0)), env, eff, level, bindings, ir.Tail))
    ir.Cons -> Done(prim(cons(), env, eff, level, bindings, ir.Cons))
    ir.Empty ->
      Done(prim(t.Record(t.Empty), env, eff, level, bindings, ir.Empty))
    ir.Extend(label) ->
      Done(prim(extend(label), env, eff, level, bindings, ir.Extend(label)))
    ir.Overwrite(label) ->
      Done(prim(
        overwrite(label),
        env,
        eff,
        level,
        bindings,
        ir.Overwrite(label),
      ))
    ir.Select(label) ->
      Done(prim(select(label), env, eff, level, bindings, ir.Select(label)))
    ir.Tag(label) ->
      Done(prim(tag(label), env, eff, level, bindings, ir.Tag(label)))
    ir.Case(label) ->
      Done(prim(case_(label), env, eff, level, bindings, ir.Case(label)))
    ir.NoCases -> Done(prim(nocases(), env, eff, level, bindings, ir.NoCases))
    ir.Perform(label) ->
      Done(prim(perform(label), env, eff, level, bindings, ir.Perform(label)))
    ir.Handle(label) ->
      Done(prim(handle(label), env, eff, level, bindings, ir.Handle(label)))
    ir.Builtin(id) ->
      case builtin(id) {
        Ok(poly) -> Done(prim(poly, env, eff, level, bindings, ir.Builtin(id)))
        Error(Nil) -> {
          let #(type_, bindings) = binding.mono(level, bindings)
          let meta = #(Error(error.MissingBuiltin(id)), type_, t.Empty, env)
          Done(#(bindings, type_, eff, #(ir.Builtin(id), meta)))
        }
      }
    ir.Reference(reference) -> lookup_ref(reference, env, eff, level, bindings)
  }
}

/// A let or application waiting for the expression to its right.
type Frame(annotation) {
  Bind(label: String, value: ir.Node(annotation), env: Env)
  Call(function: ir.Node(annotation), type_: binding.Mono, level: Int, env: Env)
}

/// Walk and rebuild long source spines with heap frames rather than the
/// JavaScript call stack, including when a deeply nested reference suspends.
fn spine(source, env, eff, level, bindings, frames) {
  let #(exp, _meta) = source
  case exp {
    ir.Let(label, value, body) -> {
      let inner_level = level + 1
      case do_infer(value, env, eff, inner_level, bindings) {
        Done(#(bindings, ty_value, eff, value)) -> {
          let #(env, frames) =
            bind_frame(label, value, ty_value, env, frames, level, bindings)
          spine(body, env, eff, level, bindings, frames)
        }
        lookup -> {
          use #(bindings, ty_value, eff, value) <- bind(lookup)
          let #(env, frames) =
            bind_frame(label, value, ty_value, env, frames, level, bindings)
          spine(body, env, eff, level, bindings, frames)
        }
      }
    }
    // Evaluating the function and argument uses the surrounding effect;
    // applying the function is accounted for while unwinding the call frame.
    ir.Apply(function, argument) -> {
      let inner_level = level + 1
      case do_infer(function, env, eff, inner_level, bindings) {
        Done(#(bindings, ty_function, eff, function)) ->
          spine(argument, env, eff, inner_level, bindings, [
            Call(function:, type_: ty_function, level:, env:),
            ..frames
          ])
        lookup -> {
          use #(bindings, ty_function, eff, function) <- bind(lookup)
          spine(argument, env, eff, inner_level, bindings, [
            Call(function:, type_: ty_function, level:, env:),
            ..frames
          ])
        }
      }
    }
    _ ->
      case do_infer(source, env, eff, level, bindings) {
        Done(#(bindings, type_, eff, tree)) ->
          Done(unwind(frames, bindings, type_, eff, tree))
        lookup -> {
          use #(bindings, type_, eff, tree) <- bind(lookup)
          Done(unwind(frames, bindings, type_, eff, tree))
        }
      }
  }
}

fn bind_frame(label, value, ty_value, env, frames, level, bindings) {
  let scheme = binding.gen(close(ty_value, level, bindings), level, bindings)
  #([#(label, scheme), ..env], [Bind(label:, value:, env:), ..frames])
}

fn unwind(frames, bindings, type_, eff, tree) {
  case frames {
    [] -> #(bindings, type_, eff, tree)
    [Bind(label:, value:, env:), ..frames] -> {
      let meta = #(Ok(Nil), type_, t.Empty, env)
      unwind(frames, bindings, type_, eff, #(ir.Let(label, value, tree), meta))
    }
    [Call(function:, type_: ty_function, level:, env:), ..frames] -> {
      let inner_level = level + 1
      let #(ty_return, bindings) = binding.mono(inner_level, bindings)
      let #(test_eff, bindings) = binding.mono(inner_level, bindings)

      let #(bindings, result) = case
        unify.unify(
          t.Fun(type_, test_eff, ty_return),
          ty_function,
          inner_level,
          bindings,
        )
      {
        Ok(bindings) -> #(bindings, Ok(Nil))
        Error(reason) -> #(bindings, Error(reason))
      }

      let #(last, mapped) = eff_tail(binding.resolve(test_eff, bindings))
      let raised = case last {
        Error(Nil) -> test_eff
        Ok(i) -> {
          let assert Ok(binding) = dict.get(bindings, i)
          case binding {
            binding.Unbound(l) if l > level - 1 -> mapped
            _ -> test_eff
          }
        }
      }

      let #(bindings, result) = case
        unify.unify(test_eff, eff, level, bindings)
      {
        Ok(bindings) -> #(bindings, result)
        Error(reason) -> #(bindings, case result {
          Ok(Nil) -> Error(reason)
          Error(reason) -> Error(reason)
        })
      }
      let record = close(ty_return, level, bindings)
      let meta = #(result, record, raised, env)
      unwind(frames, bindings, ty_return, eff, #(ir.Apply(function, tree), meta))
    }
  }
}

fn lookup_ref(reference, env, eff, level, bindings) {
  Lookup(reference:, resume: fn(answer) {
    case answer {
      Ok(poly) ->
        Done(prim(poly, env, eff, level, bindings, ir.Reference(reference)))
      Error(reason) -> {
        let #(type_, bindings) = binding.mono(level, bindings)
        let meta = #(Error(reason), type_, t.Empty, env)
        Done(#(bindings, type_, eff, #(ir.Reference(reference), meta)))
      }
    }
  })
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

// The value built by fix is always applied to the self reference, which at
// runtime is a function. Therefore the fixed value must be a function,
// `((a) -> b)` and the constructor has type `((a) -> b) -> ((a) -> b)`.
// The constructor itself is pure.
pub fn fix() {
  let self = t.Fun(q(0), q(1), q(2))
  t.Fun(t.Fun(self, t.Empty, self), t.Empty, self)
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
    // the self reference passed to the constructor is always a function,
    // so the fixed value must be a function too
    #("fix", fix()),
    // TODO do we want a never type
    #("never", pure1(t.Never, q(1))),

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
      let return = t.record([#("pre", t.String), #("post", t.String)])
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
    #("binary_size", pure1(t.Binary, t.Integer)),
    #("binary_concat", pure2(t.Binary, t.Binary, t.Binary)),
    #("binary_compare", {
      let return = t.union([#("Lt", t.unit), #("Eq", t.unit), #("Gt", t.unit)])
      pure2(t.Binary, t.Binary, return)
    }),
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
