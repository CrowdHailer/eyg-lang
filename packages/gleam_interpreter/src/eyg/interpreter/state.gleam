import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/list
import gleam/result

pub type Context(m) =
  #(List(#(Kontinue(m), m)), Env(m))

pub type Value(m) =
  v.Value(m, Context(m))

pub type Reason(m) =
  break.Reason(m, Context(m))

pub type Control(m) {
  E(#(ir.Expression(m), m))
  V(Value(m))
}

pub type Debug(m) =
  #(Reason(m), m, Env(m), Stack(m))

pub type Next(m) {
  Loop(Control(m), Env(m), Stack(m))
  Break(Result(Value(m), Debug(m)))
}

// Env and Stack(m) also rely on each other
pub type Env(m) {
  Env(
    scope: List(#(String, Value(m))),
    references: dict.Dict(String, Value(m)),
    builtins: dict.Dict(String, Builtin(m)),
  )
}

pub type Return(m) =
  Result(#(Control(m), Env(m), Stack(m)), Reason(m))

pub type Builtin(m) {
  Arity1(fn(Value(m), m, Env(m), Stack(m)) -> Return(m))
  Arity2(fn(Value(m), Value(m), m, Env(m), Stack(m)) -> Return(m))
  Arity3(fn(Value(m), Value(m), Value(m), m, Env(m), Stack(m)) -> Return(m))
  Arity4(
    fn(Value(m), Value(m), Value(m), Value(m), m, Env(m), Stack(m)) -> Return(m),
  )
}

pub type Stack(m) {
  Stack(Kontinue(m), m, Stack(m))
  Empty(Dict(String, Extrinsic(m)))
}

pub type Kontinue(m) {
  Arg(ir.Node(m), Env(m))
  Apply(Value(m), Env(m))
  Assign(String, ir.Node(m), Env(m))
  CallWith(Value(m), Env(m))
  Delimit(String, Value(m), Env(m), Bool)
}

pub type Extrinsic(m) =
  fn(Value(m)) -> Result(Value(m), Reason(m))

pub fn step(c, env, k) {
  case c, k {
    E(exp), k -> try(eval(exp, env, k))
    V(value), Empty(_) -> Break(Ok(value))
    V(value), Stack(k, meta, rest) -> try(apply(value, env, k, meta, rest))
  }
}

pub fn try(return) {
  case return {
    Ok(#(c, e, k)) -> Loop(c, e, k)
    Error(info) -> Break(Error(info))
  }
}

pub fn eval(exp, env: Env(m), k) {
  let #(exp, meta) = exp
  let value = fn(value) { Ok(#(V(value), env, k)) }
  case exp {
    ir.Lambda(param, body) ->
      Ok(#(V(v.Closure(param, body, env.scope)), env, k))

    ir.Apply(f, arg) -> Ok(#(E(f), env, Stack(Arg(arg, env), meta, k)))

    ir.Variable(x) ->
      case list.key_find(env.scope, x) {
        Ok(term) -> Ok(#(V(term), env, k))
        Error(Nil) -> Error(break.UndefinedVariable(x))
      }

    ir.Let(var, value, then) ->
      Ok(#(E(value), env, Stack(Assign(var, then, env), meta, k)))

    ir.Binary(data) -> value(v.Binary(data))
    ir.Integer(data) -> value(v.Integer(data))
    ir.String(data) -> value(v.String(data))
    ir.Tail -> value(v.LinkedList([]))
    ir.Cons -> value(v.Partial(v.Cons, []))
    ir.Vacant -> Error(break.Vacant)
    ir.Select(label) -> value(v.Partial(v.Select(label), []))
    ir.Tag(label) -> value(v.Partial(v.Tag(label), []))
    ir.Perform(label) -> value(v.Partial(v.Perform(label), []))
    ir.Empty -> value(v.unit())
    ir.Extend(label) -> value(v.Partial(v.Extend(label), []))
    ir.Overwrite(label) -> value(v.Partial(v.Overwrite(label), []))
    ir.Case(label) -> value(v.Partial(v.Match(label), []))
    ir.NoCases -> value(v.Partial(v.NoCases, []))
    ir.Handle(label) -> value(v.Partial(v.Handle(label), []))
    ir.Builtin(identifier) ->
      case dict.get(env.builtins, identifier) {
        Ok(_) -> value(v.Partial(v.Builtin(identifier), []))
        _ -> Error(break.UndefinedBuiltin(identifier))
      }
    ir.Reference(ref) ->
      case dict.get(env.references, ref) {
        Ok(v) -> value(v)
        Error(Nil) -> Error(break.UndefinedReference(ref))
      }
    ir.Release(package, release, cid) ->
      Error(break.UndefinedRelease(package, release, cid))
  }
  |> result.map_error(fn(reason) { #(reason, meta, env, k) })
}

pub fn apply(value, env, k, meta, rest) {
  case k {
    Assign(label, then, env) -> {
      let env = Env(..env, scope: [#(label, value), ..env.scope])
      Ok(#(E(then), env, rest))
    }
    Arg(arg, env) -> Ok(#(E(arg), env, Stack(Apply(value, env), meta, rest)))
    Apply(f, env) -> call(f, value, meta, env, rest)
    CallWith(arg, env) -> call(value, arg, meta, env, rest)
    Delimit(_, _, _, _) -> Ok(#(V(value), env, rest))
  }
  |> result.map_error(fn(reason) { #(reason, meta, env, rest) })
}

pub fn call(f, arg, meta, env: Env(m), k: Stack(m)) {
  case f {
    v.Closure(param, body, captured) -> {
      let env = Env(..env, scope: [#(param, arg), ..captured])
      Ok(#(E(body), env, k))
    }
    // builtin needs to return result for the case statement
    // Resume/Deep need access to k nothing needs access to env but extension might change that
    v.Partial(switch, applied) ->
      case switch, applied {
        v.Cons, [item] -> {
          use elements <- result.then(cast.as_list(arg))
          Ok(#(V(v.LinkedList([item, ..elements])), env, k))
        }
        v.Extend(label), [value] -> {
          use fields <- result.then(cast.as_record(arg))
          let fields = dict.insert(fields, label, value)
          Ok(#(V(v.Record(fields)), env, k))
        }
        v.Overwrite(label), [value] -> {
          use fields <- result.then(cast.as_record(arg))
          use _ <- result.then(
            dict.get(fields, label)
            |> result.replace_error(break.MissingField(label)),
          )
          let fields = dict.insert(fields, label, value)
          Ok(#(V(v.Record(fields)), env, k))
        }
        v.Select(label), [] -> {
          use fields <- result.then(cast.as_record(arg))
          use value <- result.then(
            dict.get(fields, label)
            |> result.replace_error(break.MissingField(label)),
          )
          Ok(#(V(value), env, k))
        }
        v.Tag(label), [] -> Ok(#(V(v.Tagged(label, arg)), env, k))
        v.Match(label), [branch, otherwise] -> {
          use #(l, inner) <- result.then(cast.as_tagged(arg))
          case l == label {
            True -> call(branch, inner, meta, env, k)
            False -> call(otherwise, arg, meta, env, k)
          }
        }
        v.NoCases, [] -> Error(break.NoMatch(arg))
        v.Perform(label), [] -> perform(label, arg, env, k)
        v.Handle(label), [handler] -> deep(label, handler, arg, meta, env, k)
        v.Resume(#(popped, env)), [] -> Ok(#(V(arg), env, move(popped, k)))
        v.Builtin(key), applied ->
          call_builtin(key, list.append(applied, [arg]), meta, env, k)

        switch, _ -> {
          let applied = list.append(applied, [arg])
          Ok(#(V(v.Partial(switch, applied)), env, k))
        }
      }

    term -> Error(break.NotAFunction(term))
  }
}

// can return a expression body
fn call_builtin(key, applied, meta, env: Env(m), kont) {
  case dict.get(env.builtins, key) {
    Ok(func) ->
      case func, applied {
        // impl uses path to build stack when calling functions passed in
        // might not need it as fn's keep track of path
        Arity1(impl), [x] -> impl(x, meta, env, kont)
        Arity2(impl), [x, y] -> impl(x, y, meta, env, kont)
        Arity3(impl), [x, y, z] -> impl(x, y, z, meta, env, kont)
        Arity4(impl), [x, y, z, a] -> impl(x, y, z, a, meta, env, kont)
        _, _args -> Ok(#(V(v.Partial(v.Builtin(key), applied)), env, kont))
      }
    Error(Nil) -> Error(break.UndefinedBuiltin(key))
  }
}

// In interpreter because circular dependencies interpreter -> spec -> stdlib/linked list

fn move(delimited, acc) {
  case delimited {
    [] -> acc
    [#(step, meta), ..rest] -> move(rest, Stack(step, meta, acc))
  }
}

fn do_perform(label, arg, i_env, k, acc) {
  case k {
    // shallow is always false
    Stack(Delimit(l, h, e, shallow), meta, rest) if l == label -> {
      let acc = case shallow {
        True -> acc
        False -> [#(Delimit(label, h, e, False), meta), ..acc]
      }
      let resume = v.Partial(v.Resume(#(acc, i_env)), [])
      let k =
        Stack(CallWith(arg, e), meta, Stack(CallWith(resume, e), meta, rest))
      Ok(#(V(h), e, k))
    }
    Stack(kontinue, meta, rest) ->
      do_perform(label, arg, i_env, rest, [#(kontinue, meta), ..acc])
    Empty(extrinsic) -> {
      // inefficient to move back in error case
      let original_k = move(acc, Empty(extrinsic))
      case dict.get(extrinsic, label) {
        Ok(handler) ->
          case handler(arg) {
            Ok(term) -> Ok(#(V(term), i_env, original_k))
            Error(reason) -> Error(reason)
          }
        Error(Nil) -> Error(break.UnhandledEffect(label, arg))
      }
    }
  }
}

pub fn perform(label, arg, i_env, k: Stack(m)) {
  do_perform(label, arg, i_env, k, [])
}

// rename handle and move the handle for runner with handles out
pub fn deep(label, handle, exec, meta, env, k) {
  let k = Stack(Delimit(label, handle, env, False), meta, k)
  call(exec, v.unit(), meta, env, k)
}
// somewhere this needs outer k
// fn shallow(label, handle, exec, meta, env, k) {
//   let k = Stack(Delimit(label, handle, env, True), meta, k)
//   call(exec, v.unit(), meta, env, k)
// }
