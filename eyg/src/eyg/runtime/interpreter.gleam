import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eygir/expression as e

pub type Failure {
  NotAFunction(Term)
  UndefinedVariable(String)
  Vacant
  NoCases
  UnhandledEffect(String)
  IncorrectTerm(expected: String, got: Term)
  MissingField(String)
}

pub fn run(source, env, term, extrinsic) {
  case
    eval(source, env, fn(f) { handle(eval_call(f, term, Value(_)), extrinsic) })
  {
    // could eval the f and return it by wrapping in a value and then separetly calling eval call in handle
    // Can I have a type called Running, that has a Cont but not Value, and separaetly Return with Value and not Cont
    // The eval fn above could use Not a Function Error in any case which is not a Function
    Value(term) -> Ok(term)
    Abort(failure) -> Error(failure)
    Effect(label, _, _) -> Error(UnhandledEffect(label))
    _ -> todo("should have evaluated and not be a Cont at all")
  }
}

fn handle(return, extrinsic) {
  case return {
    // Don't have stateful handlers because extrinsic handlers can hold references to
    // mutable state db files etc
    Effect(label, term, k) ->
      case map.get(extrinsic, label) {
        Ok(handler) -> handle(eval_call(handler, term, k), extrinsic)
        Error(Nil) -> Abort(UnhandledEffect(label))
      }
    Value(term) -> Value(term)
    Cont(term, k) -> handle(k(term), extrinsic)
    Abort(failure) -> Abort(failure)
  }
}

pub type Term {
  Integer(value: Int)
  Binary(value: String)
  LinkedList(elements: List(Term))
  Record(fields: List(#(String, Term)))
  Tagged(label: String, value: Term)
  Function(param: String, body: e.Expression, env: List(#(String, Term)))
  Builtin(func: fn(Term, fn(Term) -> Return) -> Return)
  Defunc(Switch)
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
    Function(param, _, _) -> string.concat(["(", param, ") -> ..."])
    Builtin(_) -> "Builtin(...)"
    Defunc(_) -> todo("defunc print")
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
}

pub fn continue(k, term) {
  Cont(term, k)
}

pub fn eval_call(f, arg, k) {
  loop(step_call(f, arg, k))
}

fn step_call(f, arg, k) {
  case f {
    Function(param, body, env) -> {
      let env = [#(param, arg), ..env]
      step(body, env, k)
    }
    // builtin needs to return result for the case statement
    Builtin(f) -> f(arg, k)
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
        Match2(label, branch, rest) -> match(label, branch, rest, arg, k)
        NoCases0 -> Abort(NoCases)
        Perform0(label) -> perform(label, arg, k)
      }

    term -> Abort(NotAFunction(term))
  }
}

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

fn step(exp: e.Expression, env, k) {
  case exp {
    e.Lambda(param, body) -> continue(k, Function(param, body, env))
    e.Apply(f, arg) ->
      step(f, env, fn(f) { step(arg, env, step_call(f, _, k)) })
    e.Variable(x) ->
      case list.key_find(env, x) {
        Ok(term) -> continue(k, term)
        Error(Nil) -> Abort(UndefinedVariable(x))
      }
    e.Let(var, value, then) ->
      step(value, env, fn(term) { step(then, [#(var, term), ..env], k) })
    e.Integer(value) -> continue(k, Integer(value))
    e.Binary(value) -> continue(k, Binary(value))
    e.Tail -> continue(k, LinkedList([]))
    e.Cons -> continue(k, Defunc(Cons0))
    e.Vacant -> Abort(Vacant)
    e.Select(label) -> continue(k, Defunc(Select0(label)))
    e.Tag(label) -> continue(k, Defunc(Tag0(label)))
    e.Perform(label) -> continue(k, Defunc(Perform0(label)))
    e.Empty -> continue(k, Record([]))
    e.Extend(label) -> continue(k, Defunc(Extend0(label)))
    e.Overwrite(label) -> continue(k, Defunc(Overwrite0(label)))
    e.Case(label) -> continue(k, Defunc(Match0(label)))
    e.NoCases -> continue(k, Defunc(NoCases0))
    e.Handle(label) -> continue(k, build_runner(label))
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

fn match(label, matched, otherwise, value, k) {
  case value {
    Tagged(l, term) ->
      case l == label {
        True -> step_call(matched, term, k)
        False -> step_call(otherwise, value, k)
      }
    term -> Abort(IncorrectTerm("Tagged", term))
  }
}

pub fn handled(label, handler, outer_k, thing) {
  case thing {
    Effect(l, lifted, resume) if l == label -> {
      use partial <- step_call(handler, lifted)

      use applied <- step_call(
        partial,
        Builtin(fn(reply, handler_k) {
          handled(label, handler, handler_k, loop(resume(reply)))
        }),
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
        fn(x) { handled(label, handler, outer_k, loop(resume(x))) },
      )
    Abort(reason) -> Abort(reason)
  }
}

pub fn runner(label, handler) {
  Builtin(fn(exec, k) {
    handled(label, handler, k, eval_call(exec, Record([]), Value))
  })
}

pub fn build_runner(label) {
  Builtin(fn(handler, k) { continue(k, runner(label, handler)) })
}

pub fn builtin2(f) {
  Builtin(fn(a, k) { continue(k, Builtin(fn(b, k) { f(a, b, k) })) })
}

pub fn builtin3(f) {
  Builtin(fn(a, k) {
    continue(
      k,
      Builtin(fn(b, k) { continue(k, Builtin(fn(c, k) { f(a, b, c, k) })) }),
    )
  })
}
