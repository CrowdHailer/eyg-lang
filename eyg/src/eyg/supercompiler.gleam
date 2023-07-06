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

pub type Control {
  E(e.Expression)
  V(Value)
}

type Env =
  List(#(String, Value))

pub type Arity {
  // I don;t want to pass in env here but I need it to be able to pass it to K
  Arity1(fn(Value, Env, fn(Value, Env) -> K) -> K)
  Arity2(fn(Value, Value, Env, fn(Value, Env) -> K) -> K)
  Arity3(fn(Value, Value, Value, Env, fn(Value, Env) -> K) -> K)
}

pub type Value {
  Integer(Int)
  Binary(String)
  LinkedList(elements: List(Value))
  Tagged(label: String, value: Value)
  Fn(String, e.Expression, Env)
  Defunc(Switch, List(Value))
  Residual(e.Expression)
}

pub type Switch {
  // Cons0
  // Cons1(Term)
  // Extend0(String)
  // Extend1(String, Term)
  // Overwrite0(String)
  // Overwrite1(String, Term)
  // Select0(String)
  Tag(String)
  // Match0(String)
  // Match1(String, Term)
  // Match2(String, Term, Term)
  // NoCases0
  // Perform0(String)
  // Handle0(String)
  // Handle1(String, Term)
  // Resume(String, Term, fn(Term) -> Return)
  // Shallow0(String)
  // Shallow1(String, Term)
  // ShallowResume(fn(Term) -> Return)
  Builtin(Arity)
}

pub type K {
  Done(e.Expression)
  K(Control, Env, fn(Value, Env) -> K)
}

pub fn step(control, env, k) {
  case control {
    E(e.Variable(var)) -> {
      let assert Ok(value) = list.key_find(env, var)
      K(V(value), env, k)
    }
    E(e.Lambda(param, body)) -> {
      let env = [#(param, Residual(e.Variable(param))), ..env]
      use body, _env <- K(E(body), env)
      K(V(Fn(param, to_expression(body), env)), env, k)
    }
    E(e.Apply(func, arg)) -> {
      use func, env <- K(E(func), env)
      use arg, env <- K(E(arg), env)
      case func {
        Fn(param, body, captured) -> K(E(body), [#(param, arg), ..captured], k)
        Defunc(func, applied) -> {
          let applied = list.append(applied, [arg])
          case func, applied {
            Tag(label), [x] -> K(V(Tagged(label, x)), env, k)
            // don't pass k or env to builtin?
            Builtin(Arity1(impl)), [x] -> impl(x, env, k)
            Builtin(Arity2(impl)), [x, y] -> impl(x, y, env, k)
            Builtin(Arity3(impl)), [x, y, z] -> impl(x, y, z, env, k)
            _, args -> K(V(Defunc(func, applied)), env, k)
          }
        }
        _ -> {
          io.debug(func)
          todo("in apply")
        }
      }
    }
    E(e.Let(label, body, then)) -> {
      use value, env <- K(E(body), env)
      K(E(then), [#(label, value), ..env], k)
    }
    E(e.Vacant(comment)) -> K(V(Residual(e.Vacant(comment))), env, k)
    E(e.Integer(i)) -> K(V(Integer(i)), env, k)
    E(e.Binary(b)) -> K(V(Binary(b)), env, k)
    E(e.Tail) -> K(V(LinkedList([])), env, k)
    E(e.Cons) -> K(V(Defunc(builtin("Cons"), [])), env, k)
    E(e.Tag(label)) -> K(V(Defunc(Tag(label), [])), env, k)
    E(e.Builtin(key)) -> K(V(Defunc(builtin(key), [])), env, k)
    V(value) -> k(value, env)
    _ -> {
      io.debug(#("control---", control))
      todo("supeswer")
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
    Tagged(label, value) -> e.Apply(e.Tag(label), to_expression(value))
    Fn(param, body, _env) -> e.Lambda(param, body)
    Defunc(arity, applied) -> todo("defunc")
    Residual(exp) -> exp
  }
}

pub fn eval(exp) {
  do_eval(E(exp), [], fn(value, _e) { Done(to_expression(value)) })
}

fn do_eval(control, e, k) {
  case step(control, e, k) {
    Done(value) -> value
    K(control, e, k) -> do_eval(control, e, k)
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
  }
  |> Builtin
}

pub fn do_cons(head, tail, env, k) {
  let v = case tail {
    LinkedList(elements) -> LinkedList([head, ..elements])
    Residual(exp) -> todo("cons residual")
    // term -> Abort(IncorrectTerm("LinkedList", term))
    _ -> panic("cons")
  }
  K(V(v), env, k)
}

// pub fn do_tag(value, env, k) {
//   todo
// }

pub fn do_lang_eval(v, env, k) {
  let assert LinkedList(source) = v
  let assert Ok(exp) = language_to_expression(source)
  eval(exp)
  io.debug(exp)
  // todo
  K(E(exp), env, k)
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
    // [Tagged("Apply", Record([])), ..rest] -> {
    //   use func, rest <- do_language_to_expression(rest)
    //   use arg, rest <- do_language_to_expression(rest)
    //   k(e.Apply(func, arg), rest)
    // }
    [Tagged("Let", Binary(label)), ..rest] -> {
      use value, rest <- do_language_to_expression(rest)
      use then, rest <- do_language_to_expression(rest)
      k(e.Let(label, value, then), rest)
    }

    [Tagged("Integer", Integer(value)), ..rest] -> k(e.Integer(value), rest)
    [Tagged("Binary", Binary(value)), ..rest] -> k(e.Binary(value), rest)

    // [Tagged("Tail", Record([])), ..rest] -> k(e.Tail, rest)
    // [Tagged("Cons", Record([])), ..rest] -> k(e.Cons, rest)
    [Tagged("Vacant", Binary(comment)), ..rest] -> k(e.Vacant(comment), rest)

    // [Tagged("Empty", Record([])), ..rest] -> k(e.Empty, rest)
    [Tagged("Extend", Binary(label)), ..rest] -> k(e.Extend(label), rest)
    [Tagged("Select", Binary(label)), ..rest] -> k(e.Select(label), rest)
    [Tagged("Overwrite", Binary(label)), ..rest] -> k(e.Overwrite(label), rest)
    [Tagged("Tag", Binary(label)), ..rest] -> k(e.Tag(label), rest)
    [Tagged("Case", Binary(label)), ..rest] -> k(e.Case(label), rest)

    // [Tagged("NoCases", Record([])), ..rest] -> k(e.NoCases, rest)
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

pub fn do_uppercase(v, env, k) {
  let v = case v {
    Binary(b) -> Binary(string.uppercase(b))
    Residual(e) -> Residual(e.Apply(e.Builtin("string_uppercase"), e))
    _ -> panic("invalid")
  }
  k(v, env)
}

pub fn do_append(a, b, env, k) {
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
  k(v, env)
}

pub fn do_absolute(v, env, k) {
  let v = case v {
    Integer(i) -> Integer(int.absolute_value(i))
    Residual(e) -> Residual(e.Apply(e.Builtin("integer_absolute"), e))
    _ -> panic("invalid")
  }
  k(v, env)
}

pub fn do_add(x, y, env, k) {
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
  k(v, env)
}
// NEED to pass expression to Defuncs
// do_match
