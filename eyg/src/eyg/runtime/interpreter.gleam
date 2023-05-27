import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eygir/expression as e
import gleam/javascript/promise.{Promise as JSPromise}

pub type Failure {
  NotAFunction(Term)
  UndefinedVariable(String)
  Vacant(comment: String)
  NoCases
  UnhandledEffect(String, Term)
  IncorrectTerm(expected: String, got: Term)
  MissingField(String)
}

pub fn run(source, env, term, extrinsic) {
  case
    eval(
      source,
      env,
      fn(f) {
        handle(
          eval_call(f, term, env.builtins, Value(_)),
          env.builtins,
          extrinsic,
        )
      },
    )
  {
    // could eval the f and return it by wrapping in a value and then separetly calling eval call in handle
    // Can I have a type called Running, that has a Cont but not Value, and separaetly Return with Value and not Cont
    // The eval fn above could use Not a Function Error in any case which is not a Function
    Value(term) -> Ok(term)
    Abort(failure) -> Error(failure)
    Effect(label, lifted, _) -> Error(UnhandledEffect(label, lifted))
    Cont(_, _) -> panic("should have evaluated and not be a Cont at all")
    // other runtime errors return error, maybe this should be the same
    Async(_, _) ->
      panic(
        "cannot return async value some sync run. This effect would not be allowed by type system",
      )
  }
}

pub fn run_async(source, env, term, extrinsic) {
  let ret =
    eval(
      source,
      env,
      fn(f) {
        handle(
          eval_call(f, term, env.builtins, Value(_)),
          env.builtins,
          extrinsic,
        )
      },
    )
  flatten_promise(ret, env, extrinsic)
}

pub fn flatten_promise(ret, env: Env, extrinsic) {
  case ret {
    // could eval the f and return it by wrapping in a value and then separetly calling eval call in handle
    // Can I have a type called Running, that has a Cont but not Value, and separaetly Return with Value and not Cont
    // The eval fn above could use Not a Function Error in any case which is not a Function
    Value(term) -> promise.resolve(Ok(term))
    Abort(failure) -> promise.resolve(Error(failure))
    Effect(label, lifted, _) ->
      promise.resolve(Error(UnhandledEffect(label, lifted)))
    Cont(_, _) -> panic("should have evaluated and not be a Cont at all")
    Async(p, k) ->
      promise.await(
        p,
        fn(return) {
          flatten_promise(
            handle(k(return), env.builtins, extrinsic),
            env,
            extrinsic,
          )
        },
      )
  }
}

pub fn handle(return, builtins, extrinsic) {
  case return {
    // Don't have stateful handlers because extrinsic handlers can hold references to
    // mutable state db files etc
    Effect(label, term, k) ->
      case map.get(extrinsic, label) {
        Ok(handler) ->
          // handle(eval_call(handler, term, builtins, k), builtins, extrinsic)
          handle(handler(term, k), builtins, extrinsic)
        Error(Nil) -> Abort(UnhandledEffect(label, term))
      }
    Value(term) -> Value(term)
    Cont(term, k) -> handle(k(term), builtins, extrinsic)
    Abort(failure) -> Abort(failure)
    Async(promise, k) -> Async(promise, k)
  }
}

pub type Term {
  Integer(value: Int)
  Binary(value: String)
  LinkedList(elements: List(Term))
  Record(fields: List(#(String, Term)))
  Tagged(label: String, value: Term)
  Function(param: String, body: e.Expression, env: List(#(String, Term)))
  Defunc(Switch)
  Promise(JSPromise(Term))
}

pub type Switch {
  Cons0
  Cons1(Term)
  Extend0(String)
  Extend1(String, Term)
  Overwrite0(String)
  Overwrite1(String, Term)
  Select0(String)
  Tag0(String)
  Match0(String)
  Match1(String, Term)
  Match2(String, Term, Term)
  NoCases0
  Perform0(String)
  Handle0(String)
  Handle1(String, Term)
  Resume(String, Term, fn(Term) -> Return)
  Builtin(String, List(Term))
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

// This might not give in runtime core, more runtime presentation
pub fn to_string(term) {
  case term {
    Integer(value) -> int.to_string(value)
    Binary(value) -> string.concat(["\"", value, "\""])
    LinkedList(items) ->
      list.map(items, to_string)
      |> list.intersperse(", ")
      |> list.prepend("[")
      |> list.append(["]"])
      |> string.concat
    Record(fields) ->
      fields
      |> list.map(field_to_string)
      |> list.intersperse(", ")
      |> list.prepend("{")
      |> list.append(["}"])
      |> string.concat
    Tagged(label, value) -> string.concat([label, "(", to_string(value), ")"])
    Function(param, _, _) -> string.concat(["(", param, ") -> { ... }"])
    Defunc(_) -> string.concat(["Defunc: "])
    Promise(_) -> string.concat(["Promise: "])
  }
}

fn field_to_string(field) {
  let #(k, v) = field
  string.concat([k, ": ", to_string(v)])
}

pub fn field(term, field) {
  case term {
    Record(fields) ->
      case list.key_find(fields, field) {
        Ok(value) -> Ok(value)
        Error(Nil) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

pub type Return {
  // It's messy to have Value and Cont, but I don't know how to do this in a tail recursive way
  // This problem will hopefully go away as I build a more sophisticated interpreter.
  // Value is needed for returning from eval/run
  // Cont is needed to break the stack (with loop).
  // I could remove Value and always return a result from run, but that would make it not easy to check correct Effects in tests.
  Value(term: Term)
  Cont(term: Term, k: fn(Term) -> Return)

  Effect(label: String, lifted: Term, continuation: fn(Term) -> Return)
  Abort(Failure)
  Async(promise: JSPromise(Term), k: fn(Term) -> Return)
}

pub fn continue(k, term) {
  Cont(term, k)
}

pub fn eval_call(f, arg, builtins, k) {
  loop(step_call(f, arg, builtins, k))
}

fn step_call(f, arg, builtins, k) {
  case f {
    Function(param, body, env) -> {
      let env = [#(param, arg), ..env]
      step(body, Env(env, builtins), k)
    }
    // builtin needs to return result for the case statement
    Defunc(switch) ->
      case switch {
        Cons0 -> continue(k, Defunc(Cons1(arg)))
        Cons1(value) -> cons(value, arg, k)
        Extend0(label) -> continue(k, Defunc(Extend1(label, arg)))
        Extend1(label, value) -> extend(label, value, arg, k)
        Overwrite0(label) -> continue(k, Defunc(Overwrite1(label, arg)))
        Overwrite1(label, value) -> overwrite(label, value, arg, k)
        Select0(label) -> select(label, arg, k)
        Tag0(label) -> continue(k, Tagged(label, arg))
        Match0(label) -> continue(k, Defunc(Match1(label, arg)))
        Match1(label, branch) -> continue(k, Defunc(Match2(label, branch, arg)))
        Match2(label, branch, rest) ->
          match(label, branch, rest, arg, builtins, k)
        NoCases0 -> Abort(NoCases)
        Perform0(label) -> perform(label, arg, k)
        Handle0(label) -> continue(k, Defunc(Handle1(label, arg)))
        Handle1(label, handler) -> runner(label, handler, arg, builtins, k)
        // Ok so I am lost as to why resume works or is it even needed
        // I think it is in the situation where someone serializes a
        // partially applied continuation function in handler
        Resume(label, handler, resume) ->
          handled(label, handler, k, loop(resume(arg)), builtins)
        Builtin(key, applied) ->
          call_builtin(key, list.append(applied, [arg]), builtins, k)
      }

    term -> Abort(NotAFunction(term))
  }
}

pub type Arity {
  Arity1(fn(Term, map.Map(String, Arity), fn(Term) -> Return) -> Return)
  Arity2(fn(Term, Term, map.Map(String, Arity), fn(Term) -> Return) -> Return)
  Arity3(
    fn(Term, Term, Term, map.Map(String, Arity), fn(Term) -> Return) -> Return,
  )
}

fn call_builtin(key, applied, builtins, kont) {
  case map.get(builtins, key) {
    Ok(func) ->
      case func, applied {
        Arity1(impl), [x] -> impl(x, builtins, kont)
        Arity2(impl), [x, y] -> impl(x, y, builtins, kont)
        Arity3(impl), [x, y, z] -> impl(x, y, z, builtins, kont)
        _, args -> continue(kont, Defunc(Builtin(key, args)))
      }

    Error(Nil) -> Abort(UndefinedVariable(key))
  }
}

// In interpreter because circular dependencies interpreter -> spec -> stdlib/linked list

// Loop is always tail recursive.
// It is used to string individual steps into an eval call.
// If not separated the eval implementation causes stack overflows.
// This is because eval needs references to itself in continuations.
pub fn loop(return) {
  case return {
    Cont(term, k) -> loop(k(term))
    return -> return
  }
}

pub fn eval(exp: e.Expression, env, k) {
  loop(step(exp, env, k))
}

pub type Env {
  Env(scope: List(#(String, Term)), builtins: map.Map(String, Arity))
}

fn step(exp: e.Expression, env: Env, k) {
  case exp {
    e.Lambda(param, body) -> continue(k, Function(param, body, env.scope))
    e.Apply(f, arg) ->
      step(f, env, fn(f) { step(arg, env, step_call(f, _, env.builtins, k)) })
    e.Variable(x) ->
      case list.key_find(env.scope, x) {
        Ok(term) -> continue(k, term)
        Error(Nil) -> Abort(UndefinedVariable(x))
      }
    e.Let(var, value, then) ->
      step(
        value,
        env,
        fn(term) {
          let env = Env(..env, scope: [#(var, term), ..env.scope])
          step(then, env, k)
        },
      )
    e.Integer(value) -> continue(k, Integer(value))
    e.Binary(value) -> continue(k, Binary(value))
    e.Tail -> continue(k, LinkedList([]))
    e.Cons -> continue(k, Defunc(Cons0))
    e.Vacant(comment) -> Abort(Vacant(comment))
    e.Select(label) -> continue(k, Defunc(Select0(label)))
    e.Tag(label) -> continue(k, Defunc(Tag0(label)))
    e.Perform(label) -> continue(k, Defunc(Perform0(label)))
    e.Empty -> continue(k, Record([]))
    e.Extend(label) -> continue(k, Defunc(Extend0(label)))
    e.Overwrite(label) -> continue(k, Defunc(Overwrite0(label)))
    e.Case(label) -> continue(k, Defunc(Match0(label)))
    e.NoCases -> continue(k, Defunc(NoCases0))
    e.Handle(label) -> continue(k, Defunc(Handle0(label)))
    e.Builtin(identifier) -> continue(k, Defunc(Builtin(identifier, [])))
  }
}

fn cons(item, tail, k) {
  case tail {
    LinkedList(elements) -> continue(k, LinkedList([item, ..elements]))
    term -> Abort(IncorrectTerm("LinkedList", term))
  }
}

fn select(label, arg, k) {
  case arg {
    Record(fields) ->
      case list.key_find(fields, label) {
        Ok(value) -> continue(k, value)
        Error(Nil) -> Abort(MissingField(label))
      }
    term -> Abort(IncorrectTerm(string.append("Record -select", label), term))
  }
}

fn perform(label, lift, resume) {
  Effect(label, lift, resume)
}

fn extend(label, value, rest, k) {
  case rest {
    Record(fields) -> continue(k, Record([#(label, value), ..fields]))
    term -> Abort(IncorrectTerm("Record -extend", term))
  }
}

fn overwrite(label, value, rest, k) {
  case rest {
    Record(fields) ->
      case list.key_pop(fields, label) {
        Ok(#(_old, fields)) -> continue(k, Record([#(label, value), ..fields]))
        Error(Nil) -> Abort(MissingField(label))
      }
    term -> Abort(IncorrectTerm("Record -overwrite", term))
  }
}

fn match(label, matched, otherwise, value, builtins, k) {
  case value {
    Tagged(l, term) ->
      case l == label {
        True -> step_call(matched, term, builtins, k)
        False -> step_call(otherwise, value, builtins, k)
      }
    term -> Abort(IncorrectTerm("Tagged", term))
  }
}

fn handled(label, handler, outer_k, thing, builtins) -> Return {
  case thing {
    Effect(l, lifted, resume) if l == label -> {
      use partial <- step_call(handler, lifted, builtins)

      use applied <- step_call(
        partial,
        // Ok so I am lost as to why resume works or is it even needed
        // I think it is in the situation where someone serializes a
        // partially applied continuation function in handler
        Defunc(Resume(label, handler, resume)),
        builtins,
      )

      continue(outer_k, applied)
    }
    Value(v) -> continue(outer_k, v)
    Cont(term, k) -> Cont(term, k)
    // Not equal to this effect
    Effect(l, lifted, resume) ->
      Effect(
        l,
        lifted,
        fn(x) { handled(label, handler, outer_k, loop(resume(x)), builtins) },
      )
    Async(exec, resume) ->
      Async(
        exec,
        fn(x) { handled(label, handler, outer_k, loop(resume(x)), builtins) },
      )
    Abort(reason) -> Abort(reason)
  }
}

pub fn runner(label, handler, exec, builtins, k) {
  handled(
    label,
    handler,
    k,
    eval_call(exec, Record([]), builtins, Value),
    builtins,
  )
}
