import gleam/io
import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eygir/expression as e
import gleam/javascript/promise.{Promise as JSPromise}
import plinth/browser/console

pub type Failure {
  NotAFunction(Term)
  UndefinedVariable(String)
  Vacant(comment: String)
  NoCases
  UnhandledEffect(String, Term)
  IncorrectTerm(expected: String, got: Term)
  MissingField(String)
}

// TODO separate interpreter from runner
// TODO separate async run from async eval

pub fn done(value) {
  Done(Value(value))
}

pub fn run(source, env, term, extrinsic) {
  case
    eval(
      source,
      env,
      fn(f) {
        // This could return step call but then env/extrinsic would be the same for initial and args
        eval_call(f, term, env, done)
        // extrinsic
        |> handle(env.builtins, extrinsic)
        |> Done
      },
    )
  {
    // could eval the f and return it by wrapping in a value and then separetly calling eval call in handle
    // Can I have a type called Running, that has a Cont but not Value, and separaetly Return with Value and not Cont
    // The eval fn above could use Not a Function Error in any case which is not a Function
    Value(term) -> Ok(term)
    Abort(failure) -> Error(failure)
    Effect(label, lifted, _env, _k) -> Error(UnhandledEffect(label, lifted))
    // Cont(_, _) -> panic("should have evaluated and not be a Cont at all")
    // other runtime errors return error, maybe this should be the same
    Async(_, _) ->
      panic(
        "cannot return async value some sync run. This effect would not be allowed by type system",
      )
  }
}

pub fn run_async(source, env, term, extrinsic) {
  // let ret =
  //   handle(
  //     eval(
  //       source,
  //       env,
  //       // fn(f) { handle(eval_call(f, term, env, done), env.builtins, extrinsic) },
  //       todo("run async"),
  //     ),
  //     // break the loop
  //     env.builtins,
  //     extrinsic,
  //   )
  // flatten_promise(ret, env, extrinsic)
  todo("extrinsic map of K's")
}

pub fn flatten_promise(ret, env: Env, extrinsic) {
  case ret {
    // could eval the f and return it by wrapping in a value and then separetly calling eval call in handle
    // Can I have a type called Running, that has a Cont but not Value, and separaetly Return with Value and not Cont
    // The eval fn above could use Not a Function Error in any case which is not a Function
    Value(term) -> promise.resolve(Ok(term))
    Abort(failure) -> promise.resolve(Error(failure))
    Effect(label, lifted, _env, _k) ->
      promise.resolve(Error(UnhandledEffect(label, lifted)))
    Async(p, k) ->
      promise.await(
        p,
        fn(return) {
          flatten_promise(
            handle(loop(V(Value(return)), env, done), env.builtins, extrinsic),
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
    Effect(label, term, env, k) ->
      case map.get(extrinsic, label) {
        Ok(handler) -> {
          // handler only gets env in captured fn's
          let #(c, e, k) = handler(term, k)
          let return = loop(c, e, k)
          handle(return, builtins, extrinsic)
        }
        Error(Nil) -> Abort(UnhandledEffect(label, term))
      }
    Value(term) -> Value(term)
    // Cont(term, k) -> handle(k(term), builtins, extrinsic)
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
  Resume(String, Term, fn(Term) -> #(Control, Env, fn(Term) -> StepR))
  Shallow0(String)
  Shallow1(String, Term)
  ShallowResume(fn(Term) -> Return)
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
    Defunc(d) -> string.concat(["Defunc: ", string.inspect(d)])
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

  Effect(label: String, lifted: Term, env: Env, continuation: fn(Term) -> StepR)
  Abort(Failure)
  Async(promise: JSPromise(Term), k: fn(Term) -> StepR)
}

pub fn eval_call(f, arg, env, k) {
  // allways produces value even if abort
  let #(c, e, k) = step_call(f, arg, env, k)
  loop(c, e, k)
}

pub external fn trace() -> String =
  "" "console.trace"

pub fn step_call(f, arg, env: Env, k) {
  case f {
    Function(param, body, captured) -> {
      let env = Env([#(param, arg), ..captured], env.builtins)
      #(E(body), env, k)
    }
    // builtin needs to return result for the case statement
    Defunc(switch) ->
      case switch {
        Cons0 -> #(V(Value(Defunc(Cons1(arg)))), env, k)
        Cons1(value) -> prim(cons(value, arg), env, k)
        Extend0(label) -> #(V(Value(Defunc(Extend1(label, arg)))), env, k)
        Extend1(label, value) -> prim(extend(label, value, arg), env, k)
        Overwrite0(label) -> #(V(Value(Defunc(Overwrite1(label, arg)))), env, k)
        Overwrite1(label, value) -> prim(overwrite(label, value, arg), env, k)
        Select0(label) -> prim(select(label, arg), env, k)
        Tag0(label) -> prim(Value(Tagged(label, arg)), env, k)
        Match0(label) -> #(V(Value(Defunc(Match1(label, arg)))), env, k)
        Match1(label, branch) -> #(
          V(Value(Defunc(Match2(label, branch, arg)))),
          env,
          k,
        )
        Match2(label, branch, rest) -> match(label, branch, rest, arg, env, k)
        NoCases0 -> prim(Abort(NoCases), env, k)
        // env is part of k
        Perform0(label) -> #(V(Effect(label, arg, env, k)), env, done)
        Handle0(label) -> #(V(Value(Defunc(Handle1(label, arg)))), env, k)
        Handle1(label, handler) -> runner(label, handler, arg, env, k)
        // Ok so I am lost as to why resume works or is it even needed
        // I think it is in the situation where someone serializes a
        // partially applied continuation function in handler
        Resume(label, handler, resume) -> resume(arg)

        Shallow0(label) -> #(V(Value(Defunc(Shallow1(label, arg)))), env, k)
        Shallow1(label, handler) -> todo("shallow1")
        // shallow(
        //   label,
        //   handler,
        //   k,
        //   eval_call(arg, Record([]), builtins, Value),
        //   builtins,
        // )
        ShallowResume(resume) -> todo("shhresume")
        //  shallow_resume(k, loop(resume(arg)), builtins)
        Builtin(key, applied) ->
          call_builtin(key, list.append(applied, [arg]), env, k)
      }

    term -> prim(Abort(NotAFunction(term)), env, k)
  }
}

pub fn prim(return, env, k) {
  #(V(return), env, k)
}

pub type Always =
  #(Control, Env, fn(Term) -> StepR)

pub type Arity {
  Arity1(fn(Term, Env, fn(Term) -> StepR) -> Always)
  Arity2(fn(Term, Term, Env, fn(Term) -> StepR) -> Always)
  Arity3(fn(Term, Term, Term, Env, fn(Term) -> StepR) -> Always)
}

fn call_builtin(key, applied, env: Env, kont) -> Always {
  case map.get(env.builtins, key) {
    Ok(func) ->
      case func, applied {
        Arity1(impl), [x] -> impl(x, env, kont)
        Arity2(impl), [x, y] -> impl(x, y, env, kont)
        Arity3(impl), [x, y, z] -> impl(x, y, z, env, kont)
        _, args -> #(V(Value(Defunc(Builtin(key, args)))), env, kont)
      }
    Error(Nil) -> prim(Abort(UndefinedVariable(key)), env, kont)
  }
}

// In interpreter because circular dependencies interpreter -> spec -> stdlib/linked list

pub type Control {
  E(e.Expression)
  V(Return)
}

// TODO rename when I fix return
pub type StepR {
  K(Control, Env, fn(Term) -> StepR)
  Done(Return)
}

pub fn eval(exp: e.Expression, env, k) {
  loop(E(exp), env, k)
}

// Loop is always tail recursive.
// It is used to string individual steps into an eval call.
// If not separated the eval implementation causes stack overflows.
// This is because eval needs references to itself in continuations.
pub fn loop(c, e, k) {
  case step(c, e, k) {
    K(c, e, k) -> loop(c, e, k)
    Done(return) -> return
  }
}

pub type Env {
  Env(scope: List(#(String, Term)), builtins: map.Map(String, Arity))
}

fn step(exp, env: Env, k) {
  case exp {
    E(e.Lambda(param, body)) ->
      K(V(Value(Function(param, body, env.scope))), env, k)
    E(e.Apply(f, arg)) -> {
      use f <- K(E(f), env)
      use arg <- K(E(arg), env)
      let #(c, e, k) = step_call(f, arg, env, k)
      K(c, e, k)
    }
    // step(f, env, fn(f) { step(arg, env, step_call(f, _, env.builtins, k)) })
    E(e.Variable(x)) -> {
      let return = case list.key_find(env.scope, x) {
        Ok(term) -> Value(term)
        Error(Nil) -> Abort(UndefinedVariable(x))
      }
      K(V(return), env, k)
    }
    E(e.Let(var, value, then)) -> {
      use value <- K(E(value), env)
      let env = Env(..env, scope: [#(var, value), ..env.scope])
      K(E(then), env, k)
    }
    E(e.Integer(value)) -> K(V(Value(Integer(value))), env, k)
    E(e.Binary(value)) -> K(V(Value(Binary(value))), env, k)
    E(e.Tail) -> K(V(Value(LinkedList([]))), env, k)
    E(e.Cons) -> K(V(Value(Defunc(Cons0))), env, k)
    E(e.Vacant(comment)) -> K(V(Abort(Vacant(comment))), env, k)
    E(e.Select(label)) -> K(V(Value(Defunc(Select0(label)))), env, k)
    E(e.Tag(label)) -> K(V(Value(Defunc(Tag0(label)))), env, k)
    E(e.Perform(label)) -> K(V(Value(Defunc(Perform0(label)))), env, k)
    E(e.Empty) -> K(V(Value(Record([]))), env, k)
    E(e.Extend(label)) -> K(V(Value(Defunc(Extend0(label)))), env, k)
    E(e.Overwrite(label)) -> K(V(Value(Defunc(Overwrite0(label)))), env, k)
    E(e.Case(label)) -> K(V(Value(Defunc(Match0(label)))), env, k)
    E(e.NoCases) -> K(V(Value(Defunc(NoCases0))), env, k)
    E(e.Handle(label)) -> K(V(Value(Defunc(Handle0(label)))), env, k)
    E(e.Shallow(label)) -> K(V(Value(Defunc(Shallow0(label)))), env, k)
    E(e.Builtin(identifier)) ->
      K(V(Value(Defunc(Builtin(identifier, [])))), env, k)
    V(Value(value)) -> k(value)
    V(other) -> Done(other)
  }
}

fn cons(item, tail) {
  case tail {
    LinkedList(elements) -> Value(LinkedList([item, ..elements]))
    term -> Abort(IncorrectTerm("LinkedList", term))
  }
}

fn select(label, arg) {
  case arg {
    Record(fields) ->
      case list.key_find(fields, label) {
        Ok(value) -> Value(value)
        Error(Nil) -> Abort(MissingField(label))
      }
    term -> Abort(IncorrectTerm(string.append("Record -select", label), term))
  }
}

fn extend(label, value, rest) {
  case rest {
    Record(fields) -> Value(Record([#(label, value), ..fields]))
    term -> Abort(IncorrectTerm("Record -extend", term))
  }
}

fn overwrite(label, value, rest) {
  case rest {
    Record(fields) ->
      case list.key_pop(fields, label) {
        Ok(#(_old, fields)) -> Value(Record([#(label, value), ..fields]))
        Error(Nil) -> Abort(MissingField(label))
      }
    term -> Abort(IncorrectTerm("Record -overwrite", term))
  }
}

fn match(label, matched, otherwise, value, env, k) {
  case value {
    Tagged(l, term) ->
      case l == label {
        // TODO E/V
        True -> step_call(matched, term, env, k)
        False -> step_call(otherwise, value, env, k)
      }
    term -> prim(Abort(IncorrectTerm("Tagged", term)), env, k)
  }
}

pub fn runner(label, handler, exec, env, k) {
  handled(label, handler, k, eval_call(exec, Record([]), env, done), env)
  // TODO remove eval_call and return control
}

fn handled(label, handler, outer_k, thing, outer_env) {
  case thing {
    Effect(l, lifted, env, resume) if l == label -> {
      let #(c, e, k) =
        step_call(
          handler,
          lifted,
          outer_env,
          fn(partial) {
            let #(c, e, k) =
              step_call(
                partial,
                // Ok so I am lost as to why resume works or is it even needed
                // I think it is in the situation where someone serializes a
                // partially applied continuation function in handler

                Defunc(Resume(
                  label,
                  handler,
                  fn(arg) {
                    #(
                      V(Value(arg)),
                      env,
                      fn(arg) {
                        let #(c, e, k) =
                          // I'm really not sure about this
                          handled(
                            label,
                            handler,
                            outer_k,
                            loop(V(Value(arg)), env, outer_k),
                            outer_env,
                          )
                        K(c, e, k)
                      },
                    )
                  },
                )),
                outer_env,
                fn(applied) { K(V(Value(applied)), outer_env, outer_k) },
              )
            K(c, e, k)
          },
        )

      #(c, e, k)
    }
    Value(v) -> #(V(Value(v)), outer_env, outer_k)
    // Not equal to this effect
    Effect(l, lifted, captured_env, resume) -> {
      let eff =
        Effect(
          l,
          lifted,
          captured_env,
          fn(x) {
            let thing = case resume(x) {
              K(c, e, k) -> loop(c, e, k)
              Done(return) -> return
            }
            let #(c, e, k) = handled(label, handler, outer_k, thing, outer_env)
            K(c, e, k)
          },
        )
      #(V(eff), outer_env, outer_k)
    }
    // Async(exec, resume) ->
    //   Async(
    //     exec,
    //     fn(x) { handled(label, handler, outer_k, loop(resume(x)), builtins) },
    //   )
    // Abort(reason) -> Abort(reason)
    _ -> {
      io.debug(thing)
      todo("deep handler")
    }
  }
}

fn shallow_resume(outer_k, thing, builtins) -> Return {
  todo
  // case thing {
  //   Value(v) -> continue(outer_k, v)
  //   Cont(term, k) -> Cont(term, k)
  //   // Not equal to this effect
  //   Effect(l, lifted, resume) ->
  //     Effect(
  //       l,
  //       lifted,
  //       fn(x) { shallow_resume(outer_k, loop(resume(x)), builtins) },
  //     )
  //   Async(exec, resume) ->
  //     Async(exec, fn(x) { shallow_resume(outer_k, loop(resume(x)), builtins) })
  //   Abort(reason) -> Abort(reason)
  // }
}

fn shallow(label, handler, outer_k, thing, builtins) -> Return {
  todo
  // case thing {
  //   Effect(l, lifted, resume) if l == label -> {
  //     use partial <- step_call(handler, lifted, builtins)

  //     use applied <- step_call(
  //       partial,
  //       // Ok so I am lost as to why resume works or is it even needed
  //       // I think it is in the situation where someone serializes a
  //       // partially applied continuation function in handler
  //       Defunc(ShallowResume(resume)),
  //       builtins,
  //     )

  //     continue(outer_k, applied)
  //   }
  //   Value(v) -> continue(outer_k, v)
  //   Cont(term, k) -> Cont(term, k)
  //   // Not equal to this effect
  //   Effect(l, lifted, resume) ->
  //     Effect(
  //       l,
  //       lifted,
  //       fn(x) { shallow(label, handler, outer_k, loop(resume(x)), builtins) },
  //     )
  //   Async(exec, resume) ->
  //     Async(
  //       exec,
  //       fn(x) { shallow(label, handler, outer_k, loop(resume(x)), builtins) },
  //     )
  //   Abort(reason) -> Abort(reason)
  // }
}
