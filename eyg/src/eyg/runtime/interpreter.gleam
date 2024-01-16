import gleam/int
import gleam/list
import gleam/dict.{type Dict}
import gleam/string
import eygir/expression as e
import gleam/javascript/promise.{type Promise as JSPromise}

pub type Failure {
  NotAFunction(Term)
  UndefinedVariable(String)
  Vacant(comment: String)
  NoMatch(term: Term)
  UnhandledEffect(String, Term)
  IncorrectTerm(expected: String, got: Term)
  MissingField(String)
}

// Solves the situation that JavaScript suffers from coloured functions
// To eval code that may be async needs to return a promise of a result
pub fn await(ret) {
  case ret {
    Abort(UnhandledEffect("Await", Promise(p)), rev, env, k) -> {
      use return <- promise.await(p)
      await(loop(V(return), rev, env, k))
    }
    other -> promise.resolve(other)
  }
}

pub type Term {
  Binary(value: BitArray)
  Integer(value: Int)
  Str(value: String)
  LinkedList(elements: List(Term))
  Record(fields: List(#(String, Term)))
  Tagged(label: String, value: Term)
  Function(
    param: String,
    body: e.Expression,
    env: List(#(String, Term)),
    path: List(Int),
  )
  Defunc(Switch, List(Term))
  Promise(JSPromise(Term))
}

pub type Switch {
  Cons
  Extend(String)
  Overwrite(String)
  Select(String)
  Tag(String)
  Match(String)
  NoCases
  Perform(String)
  Handle(String)
  // env needs terms/value and values need terms/env
  Resume(Stack, List(Int), Env)
  Shallow(String)
  Builtin(String)
}

pub type Path =
  List(Int)

// Keep Stack) outsie
pub type Kontinue {
  // arg path then call path
  Arg(e.Expression, Path, Path, Env)
  Apply(Term, Path, Env)
  Assign(String, e.Expression, Path, Env)
  CallWith(Term, Path, Env)
  Delimit(String, Term, Path, Env, Bool)
}

pub type Extrinsic =
  fn(Term) -> Result(Term, Failure)

pub type Stack {
  Stack(Kontinue, Stack)
  WillRenameAsDone(Dict(String, Extrinsic))
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
    Binary(value) -> e.print_bit_string(value)
    Integer(value) -> int.to_string(value)
    Str(value) -> string.concat(["\"", value, "\""])
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
    Function(param, _, _, _) -> string.concat(["(", param, ") -> { ... }"])
    Defunc(d, args) ->
      string.concat([
        "Defunc: ",
        string.inspect(d),
        " ",
        ..list.intersperse(list.map(args, to_string), ", ")
      ])
    Promise(_) -> string.concat(["Promise: "])
  }
}

fn field_to_string(field) {
  let #(k, v) = field
  string.concat([k, ": ", to_string(v)])
}

pub fn reason_to_string(reason) {
  case reason {
    UndefinedVariable(var) -> string.append("variable undefined: ", var)
    IncorrectTerm(expected, got) ->
      string.concat([
        "unexpected term, expected: ",
        expected,
        " got: ",
        to_string(got),
      ])
    MissingField(field) -> string.concat(["missing record field: ", field])
    NoMatch(term) -> string.concat(["no cases matched for: ", to_string(term)])
    NotAFunction(term) ->
      string.concat(["function expected got: ", to_string(term)])
    UnhandledEffect("Abort", reason) ->
      string.concat(["Aborted with reason: ", to_string(reason)])
    UnhandledEffect(effect, lift) ->
      string.concat(["unhandled effect ", effect, "(", to_string(lift), ")"])
    Vacant(note) -> string.concat(["tried to run a todo: ", note])
  }
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
  Value(term: Term)
  Abort(reason: Failure, rev: List(Int), env: Env, k: Stack)
}

pub fn eval_call(f, arg, env, k) {
  case step_call(f, arg, [], env, k) {
    K(c, rev, e, k) -> loop(c, rev, e, k)
    Done(ret) -> ret
  }
}

pub fn step_call(f, arg, rev, env: Env, k: Stack) {
  case f {
    Function(param, body, captured, rev) -> {
      let env = Env(..env, scope: [#(param, arg), ..captured])
      K(E(body), rev, env, k)
    }
    // builtin needs to return result for the case statement
    // Resume/Shallow/Deep need access to k nothing needs access to env but extension might change that
    Defunc(switch, applied) ->
      case switch, applied {
        Cons, [item] -> prim(cons(item, arg), rev, env, k)
        Extend(label), [value] -> prim(extend(label, value, arg), rev, env, k)
        Overwrite(label), [value] ->
          prim(overwrite(label, value, arg), rev, env, k)
        Select(label), [] -> prim(select(label, arg), rev, env, k)
        Tag(label), [] -> K(V(Tagged(label, arg)), rev, env, k)
        Match(label), [branch, rest] ->
          match(label, branch, rest, arg, rev, env, k)
        NoCases, [] -> Done(Abort(NoMatch(arg), rev, env, k))
        Perform(label), [] -> perform(label, arg, rev, env, k)
        Handle(label), [handler] -> deep(label, handler, arg, rev, env, k)
        // Ok so I am lost as to why resume works or is it even needed
        // I think it is in the situation where someone serializes a
        // partially applied continuation function in handler
        Resume(popped, rev, env), [] -> {
          let k = move(popped, k)
          K(V(arg), rev, env, k)
        }
        Shallow(label), [handler] -> shallow(label, handler, arg, rev, env, k)
        Builtin(key), applied ->
          call_builtin(key, list.append(applied, [arg]), rev, env, k)

        switch, _ -> {
          let applied = list.append(applied, [arg])
          K(V(Defunc(switch, applied)), rev, env, k)
        }
      }

    term -> Done(Abort(NotAFunction(term), rev, env, k))
  }
}

fn prim(return, rev, env, k) {
  case return {
    Ok(term) -> K(V(term), rev, env, k)
    Error(reason) -> Done(Abort(reason, rev, env, k))
  }
}

pub type Arity {
  Arity1(fn(Term, List(Int), Env, Stack) -> StepR)
  Arity2(fn(Term, Term, List(Int), Env, Stack) -> StepR)
  Arity3(fn(Term, Term, Term, List(Int), Env, Stack) -> StepR)
}

fn call_builtin(key, applied, rev, env: Env, kont) -> StepR {
  case dict.get(env.builtins, key) {
    Ok(func) ->
      case func, applied {
        // impl uses path to build stack when calling functions passed in
        // might not need it as fn's keep track of path
        Arity1(impl), [x] -> impl(x, rev, env, kont)
        Arity2(impl), [x, y] -> impl(x, y, rev, env, kont)
        Arity3(impl), [x, y, z] -> impl(x, y, z, rev, env, kont)
        _, _args -> K(V(Defunc(Builtin(key), applied)), rev, env, kont)
      }
    Error(Nil) -> Done(Abort(UndefinedVariable(key), rev, env, kont))
  }
}

// In interpreter because circular dependencies interpreter -> spec -> stdlib/linked list

pub type Control {
  E(e.Expression)
  V(Term)
}

// TODO rename when I fix return
pub type StepR {
  K(Control, List(Int), Env, Stack)
  Done(Return)
}

pub fn eval(exp: e.Expression, env, k) {
  loop(E(exp), [], env, k)
}

// Loop is always tail recursive.
// It is used to string individual steps into an eval call.
// If not separated the eval implementation causes stack overflows.
// This is because eval needs references to itself in continuations.
pub fn loop(c, p, e, k) {
  let next = step(c, p, e, k)
  case next {
    K(c, p, e, k) -> loop(c, p, e, k)
    Done(return) -> return
  }
}

pub fn loop_till(c, p, e, k) {
  case step(c, p, e, k) {
    K(c, p, e, k) -> loop_till(c, p, e, k)
    Done(return) -> {
      // let assert True = V(return) == c
      #(return, e)
    }
  }
}

pub fn resumable(exp: e.Expression, env, k) {
  loop_till(E(exp), [], env, k)
}

pub type Env {
  Env(scope: List(#(String, Term)), builtins: dict.Dict(String, Arity))
}

fn step(exp, rev, env: Env, k) {
  case exp {
    E(e.Lambda(param, body)) ->
      K(V(Function(param, body, env.scope, rev)), rev, env, k)
    E(e.Apply(f, arg)) -> {
      K(E(f), [0, ..rev], env, Stack(Arg(arg, [1, ..rev], rev, env), k))
    }
    E(e.Variable(x)) ->
      case list.key_find(env.scope, x) {
        Ok(term) -> K(V(term), rev, env, k)
        Error(Nil) -> Done(Abort(UndefinedVariable(x), rev, env, k))
      }
    E(e.Let(var, value, then)) -> {
      K(E(value), [0, ..rev], env, Stack(Assign(var, then, [1, ..rev], env), k))
    }

    E(e.Binary(value)) -> K(V(Binary(value)), rev, env, k)
    E(e.Integer(value)) -> K(V(Integer(value)), rev, env, k)
    E(e.Str(value)) -> K(V(Str(value)), rev, env, k)
    E(e.Tail) -> K(V(LinkedList([])), rev, env, k)
    E(e.Cons) -> K(V(Defunc(Cons, [])), rev, env, k)
    E(e.Vacant(comment)) -> Done(Abort(Vacant(comment), rev, env, k))
    E(e.Select(label)) -> K(V(Defunc(Select(label), [])), rev, env, k)
    E(e.Tag(label)) -> K(V(Defunc(Tag(label), [])), rev, env, k)
    E(e.Perform(label)) -> K(V(Defunc(Perform(label), [])), rev, env, k)
    E(e.Empty) -> K(V(Record([])), rev, env, k)
    E(e.Extend(label)) -> K(V(Defunc(Extend(label), [])), rev, env, k)
    E(e.Overwrite(label)) -> K(V(Defunc(Overwrite(label), [])), rev, env, k)
    E(e.Case(label)) -> K(V(Defunc(Match(label), [])), rev, env, k)
    E(e.NoCases) -> K(V(Defunc(NoCases, [])), rev, env, k)
    E(e.Handle(label)) -> K(V(Defunc(Handle(label), [])), rev, env, k)
    E(e.Shallow(label)) -> K(V(Defunc(Shallow(label), [])), rev, env, k)
    E(e.Builtin(identifier)) ->
      K(V(Defunc(Builtin(identifier), [])), rev, env, k)
    V(value) -> apply_k(value, k)
  }
}

fn apply_k(value, k) {
  case k {
    Stack(switch, k) ->
      case switch {
        Assign(label, then, rev, env) -> {
          let env = Env(..env, scope: [#(label, value), ..env.scope])
          K(E(then), rev, env, k)
        }
        Arg(arg, rev, call_rev, env) ->
          K(E(arg), rev, env, Stack(Apply(value, call_rev, env), k))
        Apply(f, rev, env) -> step_call(f, value, rev, env, k)
        CallWith(arg, rev, env) -> step_call(value, arg, rev, env, k)
        Delimit(_, _, _, _, _) -> {
          apply_k(value, k)
        }
      }
    WillRenameAsDone(_) -> Done(Value(value))
  }
}

fn cons(item, tail) {
  case tail {
    LinkedList(elements) -> Ok(LinkedList([item, ..elements]))
    term -> Error(IncorrectTerm("LinkedList", term))
  }
}

fn select(label, arg) {
  case arg {
    Record(fields) ->
      case list.key_find(fields, label) {
        Ok(value) -> Ok(value)
        Error(Nil) -> Error(MissingField(label))
      }
    term ->
      Error(IncorrectTerm(string.append("Record (-select) ", label), term))
  }
}

fn extend(label, value, rest) {
  case rest {
    Record(fields) -> Ok(Record([#(label, value), ..fields]))
    term -> Error(IncorrectTerm("Record (-extend) ", term))
  }
}

fn overwrite(label, value, rest) {
  case rest {
    Record(fields) ->
      case list.key_pop(fields, label) {
        Ok(#(_old, fields)) -> Ok(Record([#(label, value), ..fields]))
        Error(Nil) -> Error(MissingField(label))
      }
    term -> Error(IncorrectTerm("Record (-overwrite) ", term))
  }
}

fn match(label, matched, otherwise, value, rev, env, k) {
  case value {
    Tagged(l, term) ->
      case l == label {
        True -> step_call(matched, term, rev, env, k)
        False -> step_call(otherwise, value, rev, env, k)
      }
    term -> {
      let message = string.concat(["Tagged |", label])
      Done(Abort(IncorrectTerm(message, term), rev, env, k))
    }
  }
}

fn move(delimited, acc) {
  case delimited {
    WillRenameAsDone(_) -> acc
    Stack(step, rest) -> move(rest, Stack(step, acc))
  }
}

fn do_perform(label, arg, i_rev, i_env, k, acc) {
  case k {
    Stack(Delimit(l, h, rev, e, True), rest) if l == label -> {
      let resume = Defunc(Resume(acc, i_rev, i_env), [])
      let k =
        Stack(CallWith(arg, rev, e), Stack(CallWith(resume, rev, e), rest))
      K(V(h), rev, e, k)
    }
    Stack(Delimit(l, h, rev, e, False), rest) if l == label -> {
      let acc = Stack(Delimit(label, h, rev, e, False), acc)
      let resume = Defunc(Resume(acc, i_rev, i_env), [])
      let k =
        Stack(CallWith(arg, rev, e), Stack(CallWith(resume, rev, e), rest))
      K(V(h), rev, e, k)
    }
    Stack(kontinue, rest) ->
      do_perform(label, arg, i_rev, i_env, rest, Stack(kontinue, acc))
    WillRenameAsDone(extrinsic) -> {
      // inefficient to move back in error case
      let original_k = move(acc, WillRenameAsDone(dict.new()))
      case dict.get(extrinsic, label) {
        // handler is assumed to be simple. Value -> Value
        // if access to env/k is needed i.e. debug, should intercept at loop level
        Ok(handler) ->
          case handler(arg) {
            Ok(term) -> K(V(term), i_rev, i_env, original_k)
            Error(reason) -> Done(Abort(reason, i_rev, i_env, original_k))
          }
        Error(Nil) ->
          Done(Abort(UnhandledEffect(label, arg), i_rev, i_env, original_k))
      }
    }
  }
}

pub fn perform(label, arg, i_rev, i_env, k: Stack) {
  do_perform(label, arg, i_rev, i_env, k, WillRenameAsDone(dict.new()))
}

// rename handle and move the handle for runner with handles out
pub fn deep(label, handle, exec, rev, env, k) {
  let k = Stack(Delimit(label, handle, rev, env, False), k)
  step_call(exec, Record([]), rev, env, k)
}

// somewhere this needs outer k
fn shallow(label, handle, exec, rev, env: Env, k) {
  let k = Stack(Delimit(label, handle, rev, env, True), k)
  step_call(exec, Record([]), rev, env, k)
}
