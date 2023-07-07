import gleam/io
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/map
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/runtime/capture
import harness/stdlib
import harness/ffi/core

// reuse runtime interpreter add residual
// does wrapping in let give the right thing
// I think we pass k through builtins because of fold when you go back into program that might throw an effect like break
pub type Control {
  E(e.Expression)
  V(Value)
}

type Env =
  List(#(String, Value))

type Path =
  List(Int)

pub type Arity {
  // I don;t want to pass in env here but I need it to be able to pass it to K
  Arity1(fn(Value, Path, Env, fn(Value, Env) -> K) -> K)
  Arity2(fn(Value, Value, Path, Env, fn(Value, Env) -> K) -> K)
  Arity3(fn(Value, Value, Value, Path, Env, fn(Value, Env) -> K) -> K)
}

pub type Value {
  Integer(Int)
  Binary(String)
  LinkedList(elements: List(Value))
  Record(fields: List(#(String, Value)))
  Tagged(label: String, value: Value)
  NoCases
  Fn(param: String, body: e.Expression, rev: Path, captured: Env)
  Defunc(Switch, List(Value))
  Residual(e.Expression)
}

pub const unit = Record([])

pub const true = Tagged("True", unit)

pub const false = Tagged("False", unit)

pub fn ok(value) {
  Tagged("Ok", value)
}

pub fn error(reason) {
  Tagged("Error", reason)
}

pub type Switch {
  Cons
  Extend(String)
  Overwrite(String)
  Select(String)
  Tag(String)
  Match(String)
  // NoCases
  // Perform(String)
  // Handle(String)
  // Resume(String, Value, fn(Value) -> Return)
  // Shallow(String)
  // ShallowResume(fn(Value) -> Return)
  Builtin(String, Arity)
}

pub type K {
  Done(e.Expression)
  K(Control, List(Int), Env, fn(Value, Env) -> K)
}

pub fn step(control, rev, env, k) {
  // io.debug(#(
  //   control,
  //   env
  //   |> list.map(fn(e: #(_, _)) { e.0 }),
  //   k,
  // ))
  case control {
    E(e.Variable(var)) -> {
      case list.key_find(env, var) {
        Ok(value) -> K(V(value), rev, env, k)
        Error(Nil) -> {
          io.debug(#("no var", var, env))
          panic("no var")
        }
      }
    }
    E(e.Lambda(param, body)) -> {
      let env = [#(param, Residual(e.Variable(param))), ..env]
      use body, _env <- K(E(body), [0, ..rev], env)
      K(V(Fn(param, to_expression(body), [0, ..rev], env)), rev, env, k)
    }
    E(e.Apply(func, arg)) -> {
      use func, _env <- K(E(func), [0, ..rev], env)
      use arg, _env <- K(E(arg), [1, ..rev], env)
      apply(func, arg, rev, env, k)
    }
    E(e.Let(label, value, then)) -> {
      use value, env <- K(E(value), [0, ..rev], env)
      K(E(then), [1, ..rev], [#(label, value), ..env], k)
    }
    E(e.Vacant(comment)) -> K(V(Residual(e.Vacant(comment))), rev, env, k)
    E(e.Integer(i)) -> K(V(Integer(i)), rev, env, k)
    E(e.Binary(b)) -> K(V(Binary(b)), rev, env, k)

    E(e.Tail) -> K(V(LinkedList([])), rev, env, k)
    E(e.Cons) -> K(V(Defunc(Cons, [])), rev, env, k)

    E(e.Empty) -> K(V(Record([])), rev, env, k)
    E(e.Extend(label)) -> K(V(Defunc(Extend(label), [])), rev, env, k)
    E(e.Overwrite(label)) -> K(V(Defunc(Overwrite(label), [])), rev, env, k)
    E(e.Select(label)) -> K(V(Defunc(Select(label), [])), rev, env, k)

    E(e.Tag(label)) -> K(V(Defunc(Tag(label), [])), rev, env, k)
    E(e.Case(label)) -> K(V(Defunc(Match(label), [])), rev, env, k)
    E(e.NoCases) -> K(V(NoCases), rev, env, k)

    E(e.Builtin(key)) ->
      K(V(Defunc(Builtin(key, builtin(key)), [])), rev, env, k)

    V(value) -> k(value, env)
    _ -> {
      io.debug(#("control---", control))
      todo("supeswer")
    }
  }
}

fn apply(func, arg, rev, env, k) {
  case func {
    // Move to function path
    Fn(param, body, rev, captured) ->
      K(E(body), rev, [#(param, arg), ..captured], k)
    Defunc(func, applied) -> {
      let applied = list.append(applied, [arg])
      case func, applied {
        // Can't use builtin because need reference to label
        // could take label and return anon function but then not capturable
        Tag(label), [x] -> K(V(Tagged(label, x)), rev, env, k)
        // don't pass k or env to builtin?
        Builtin(_, Arity1(impl)), [x] -> impl(x, rev, env, k)
        Builtin(_, Arity2(impl)), [x, y] -> impl(x, y, rev, env, k)
        Builtin(_, Arity3(impl)), [x, y, z] -> impl(x, y, z, rev, env, k)
        _, args -> K(V(Defunc(func, applied)), rev, env, k)
      }
    }
    Residual(f) -> K(V(Residual(e.Apply(f, to_expression(arg)))), rev, env, k)
    _ -> {
      io.debug(func)
      todo("in apply")
    }
  }
}

fn to_expression(value) {
  case value {
    Integer(i) -> e.Integer(i)
    Binary(b) -> e.Binary(b)
    LinkedList(items) ->
      list.fold_right(
        items,
        e.Tail,
        fn(tail, item) { e.Apply(e.Apply(e.Cons, to_expression(item)), tail) },
      )
    Record(fields) ->
      list.fold_right(
        fields,
        e.Empty,
        fn(record, pair) {
          let #(label, item) = pair
          e.Apply(e.Apply(e.Extend(label), to_expression(item)), record)
        },
      )
    Tagged(label, value) -> e.Apply(e.Tag(label), to_expression(value))
    NoCases -> e.NoCases
    Fn(param, body, _path, _env) -> e.Lambda(param, body)
    Defunc(switch, args) ->
      case switch {
        Cons -> e.Cons
        Extend(label) -> e.Extend(label)
        Overwrite(label) -> e.Overwrite(label)
        Select(label) -> e.Select(label)
        Tag(label) -> e.Tag(label)
        Match(label) -> e.Case(label)
        // Perform(label) -> e.Perform(label)
        // Handle(label) -> e.Handle(label)
        //   e.Apply(e.Handle(label), to_expression(handler))
        // Resume(label, handler, _resume) -> {
        //   // possibly we do nothing as the context of the handler has been lost
        //   // Resume needs to be an expression I think
        //   e.Apply(e.Handle(label), to_expression(handler))
        //   panic(
        //     "not idea how to to_expression the func here, is it even possible",
        //   )
        // }
        // Shallow(label) -> e.Shallow(label)
        //   e.Apply(e.Shallow(label), to_expression(handler))
        // ShallowResume(_resume) -> {
        // possibly we do nothing as the context of the handler has been lost
        // Resume needs to be an expression I think
        //   panic(
        //     "not idea how to to_expression the func here, is it even possible: shallow",
        //   )
        // }
        Builtin(identifier, _) -> e.Builtin(identifier)
      }
      |> list.fold(args, _, fn(exp, arg) { e.Apply(exp, to_expression(arg)) })
    Residual(exp) -> exp
  }
}

pub fn eval(exp) {
  do_eval(
    E(exp),
    [],
    [],
    fn(value, _e) { Done(to_expression(value)) },
    map.new(),
  )
}

fn do_eval(control, rev, e, k, values) {
  case step(control, rev, e, k) {
    Done(value) -> #(value, values)
    K(control, rev, e, k) -> {
      let values = case control {
        V(v) -> map.insert(values, list.reverse(rev), v)
        _ -> values
      }
      do_eval(control, rev, e, k, values)
    }
  }
}

fn builtin(key) {
  case key {
    "Cons" -> Arity2(do_cons)
    // "Tag" -> Arity1(do_tag)
    "eval" -> Arity1(do_lang_eval)
    "string_uppercase" -> Arity1(do_uppercase)
    "string_append" -> Arity2(do_append)
    "integer_absolute" -> Arity1(do_absolute)
    "integer_add" -> Arity2(do_add)
    "list_pop" -> Arity1(do_list_pop)
    "list_fold" -> Arity3(fold_impl)
    unknown -> {
      io.debug(#("unknown", unknown))
      panic("unkown builtin")
    }
  }
}

pub fn do_cons(head, tail, rev, env, k) {
  let v = case tail {
    LinkedList(elements) -> LinkedList([head, ..elements])
    Residual(exp) -> todo("cons residual")
    // term -> Abort(IncorrectTerm("LinkedList", term))
    _ -> panic("cons")
  }
  K(V(v), rev, env, k)
}

pub fn do_list_pop(value, rev, env, k) {
  {
    use elements <- result.map(cast_list(value))
    case elements {
      [] -> error(unit)
      [head, ..tail] ->
        ok(Record([#("head", head), #("tail", LinkedList(tail))]))
    }
  }
  |> result.unwrap(Residual(to_expression(value)))
  |> V
  |> K(rev, env, k)
}

pub fn fold_impl(list, initial, func, rev, env, k) {
  {
    use elements <- result.map(cast_list(list))
    do_fold(elements, initial, func, rev, env, k)
  }
  |> result.unwrap(K(V(Residual(e.Vacant("fold implementation"))), rev, env, k))
}

pub fn do_fold(elements, state, f, rev, env, k) {
  case elements {
    // [] -> r.continue(k, state)
    // eval twice
    [e, ..rest] ->
      apply(
        f,
        e,
        rev,
        env,
        fn(f, _) {
          apply(
            f,
            state,
            rev,
            env,
            fn(state, _) { do_fold(rest, state, f, rev, env, k) },
          )
        },
      )
  }
}

fn cast_list(value) {
  case value {
    LinkedList(elements) -> Ok(elements)
    _ -> Error(Nil)
  }
}

pub fn do_lang_eval(v, rev, env, k) {
  let assert LinkedList(source) = v
  let assert Ok(exp) = language_to_expression(source)
  eval(exp)
  io.debug(exp)
  // todo
  K(E(exp), rev, env, k)
}

// copied from core uses different runtime values because here we need residual
pub fn language_to_expression(source) {
  do_language_to_expression(source, fn(x, _) { Ok(x) })
}

fn do_language_to_expression(term, k) {
  case term {
    [Tagged("Variable", Binary(label)), ..rest] -> {
      k(e.Variable(label), rest)
    }
    [Tagged("Lambda", Binary(label)), ..rest] -> {
      use body, rest <- do_language_to_expression(rest)
      k(e.Lambda(label, body), rest)
    }
    [Tagged("Apply", Record([])), ..rest] -> {
      use func, rest <- do_language_to_expression(rest)
      use arg, rest <- do_language_to_expression(rest)
      k(e.Apply(func, arg), rest)
    }
    [Tagged("Let", Binary(label)), ..rest] -> {
      use value, rest <- do_language_to_expression(rest)
      use then, rest <- do_language_to_expression(rest)
      k(e.Let(label, value, then), rest)
    }

    [Tagged("Integer", Integer(value)), ..rest] -> k(e.Integer(value), rest)
    [Tagged("Binary", Binary(value)), ..rest] -> k(e.Binary(value), rest)

    [Tagged("Tail", Record([])), ..rest] -> k(e.Tail, rest)
    [Tagged("Cons", Record([])), ..rest] -> k(e.Cons, rest)
    [Tagged("Vacant", Binary(comment)), ..rest] -> k(e.Vacant(comment), rest)

    [Tagged("Empty", Record([])), ..rest] -> k(e.Empty, rest)
    [Tagged("Extend", Binary(label)), ..rest] -> k(e.Extend(label), rest)
    [Tagged("Select", Binary(label)), ..rest] -> k(e.Select(label), rest)
    [Tagged("Overwrite", Binary(label)), ..rest] -> k(e.Overwrite(label), rest)
    [Tagged("Tag", Binary(label)), ..rest] -> k(e.Tag(label), rest)
    [Tagged("Case", Binary(label)), ..rest] -> k(e.Case(label), rest)

    [Tagged("NoCases", Record([])), ..rest] -> k(e.NoCases, rest)
    [Tagged("Perform", Binary(label)), ..rest] -> k(e.Perform(label), rest)
    [Tagged("Handle", Binary(label)), ..rest] -> k(e.Handle(label), rest)
    [Tagged("Shallow", Binary(label)), ..rest] -> k(e.Shallow(label), rest)
    [Tagged("Builtin", Binary(identifier)), ..rest] ->
      k(e.Builtin(identifier), rest)
    remaining -> {
      io.debug(#("remaining values", remaining))
      Error("too many expressions")
    }
  }
}

pub fn do_uppercase(v, rev, env, k) {
  let v = case v {
    Binary(b) -> Binary(string.uppercase(b))
    Residual(e) -> Residual(e.Apply(e.Builtin("string_uppercase"), e))
    _ -> panic("invalid")
  }
  K(V(v), rev, env, k)
}

pub fn do_append(a, b, rev, env, k) {
  let v = case a, b {
    Binary(a), Binary(b) -> Binary(string.append(a, b))
    Residual(x), Binary(b) ->
      Residual(e.Apply(e.Apply(e.Builtin("string_append"), x), e.Binary(b)))
    Binary(a), Residual(y) ->
      Residual(e.Apply(e.Apply(e.Builtin("string_append"), e.Binary(a)), y))
    Residual(x), Residual(y) ->
      Residual(e.Apply(e.Apply(e.Builtin("string_append"), x), y))
    _, _ -> panic("invalid")
  }
  K(V(v), rev, env, k)
}

pub fn do_absolute(v, rev, env, k) {
  let v = case v {
    Integer(i) -> Integer(int.absolute_value(i))
    Residual(e) -> Residual(e.Apply(e.Builtin("integer_absolute"), e))
    _ -> panic("invalid")
  }
  K(V(v), rev, env, k)
}

pub fn do_add(x, y, rev, env, k) {
  let v = case x, y {
    Integer(i), Integer(j) -> Integer(i + j)
    Residual(x), Integer(j) ->
      Residual(e.Apply(e.Apply(e.Builtin("integer_add"), x), e.Integer(j)))
    Integer(i), Residual(y) ->
      Residual(e.Apply(e.Apply(e.Builtin("integer_add"), e.Integer(i)), y))
    Residual(x), Residual(y) ->
      Residual(e.Apply(e.Apply(e.Builtin("integer_add"), x), y))
    _, _ -> panic("invalid")
  }
  K(V(v), rev, env, k)
}
// NEED to pass expression to Defuncs
// do_match
