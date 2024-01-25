import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import gleam/string
import glexer
import glexer/token as t
import glance as g

pub fn prelude() {
  // todo module for prelude namespacing
  dict.from_list([
    #("Nil", R("Nil", [])),
    #("True", R("True", [])),
    #("False", R("False", [])),
    // probably a record fn needed
    #(
      "Ok",
      Builtin(
        Arity1(fn(v, env, ks) { apply(R("Ok", [g.Field(None, v)]), env, ks) }),
      ),
    ),
    #(
      "Error",
      Builtin(
        Arity1(fn(v, env, ks) { apply(R("Error", [g.Field(None, v)]), env, ks) }),
      ),
    ),
  ])
}

pub type Value {
  I(Int)
  F(Float)
  S(String)
  T(List(Value))
  L(List(Value))
  R(String, List(g.Field(Value)))
  Closure(List(g.FnParameter), List(g.Statement), Env)
  // this will be module env
  ClosureLabeled(List(g.FunctionParameter), List(g.Statement), Env)
  Captured(function: Value, before: List(Value), after: List(Value))
  Builtin(Arity)
  Module(Dict(String, Value))
}

// Need builtins to be string  based before we can extract
pub type Arity {
  TupleConstructor(size: Int, gathered: List(Value))
  Arity1(fn(Value, Env, List(K)) -> Result(Value, Reason))
  Arity2(fn(Value, Value, Env, List(K)) -> Result(Value, Reason))
}

// move to reason.gleam after moving out value.gleam
pub type Reason {
  NotAFunction(Value)
  IncorrectArity(expected: Int, given: Int)
  UndefinedVariable(String)
  Panic(message: Option(String))
  Todo(message: Option(String))
  OutOfRange(size: Int, given: Int)
  NoMatch(values: List(Value))
  IncorrectTerm(expected: String, got: Value)
  FailedAssignment(pattern: g.Pattern, value: Value)
  MissingField(String)
  Finished(Dict(String, Value))
}

pub fn module(src) {
  // TODO update env with imports
  use mod <- try(g.module(src))
  let fns =
    list.map(mod.functions, fn(definition) {
      let g.Definition([], f) = definition
      #(f.name, ClosureLabeled(f.parameters, f.body, dict.new()))
    })

  Ok(Module(dict.from_list(fns)))
}

pub fn exec(statements: List(g.Statement), env) -> Result(_, Reason) {
  let [statement, ..rest] = statements
  let ks = case rest {
    [] -> []
    rest -> [Continue(rest)]
  }
  do_exec(statement, env, ks)
}

fn do_exec(statement, env, ks) {
  case statement {
    g.Expression(exp) -> do_eval(exp, env, ks)
    // We do the same
    g.Assignment(_kind, pattern, _annotation, exp) -> {
      let ks = [Assign(pattern), ..ks]
      do_eval(exp, env, ks)
    }
    // TODO why no patterns in fns but there are patterns in use?
    g.Use(patterns, func) -> {
      let assert [Continue(body), ..ks] = ks
      let parameters =
        list.map(patterns, fn(p) {
          let assert g.PatternVariable(x) = p
          g.FnParameter(g.Named(x), None)
        })
      let last_arg = g.Field(None, g.Fn(parameters, None, body))
      let #(exp, args) = case func {
        g.Call(f, args) -> #(f, list.append(args, [last_arg]))
        other -> #(other, [last_arg])
      }
      let ks = [Args(args), ..ks]
      do_eval(exp, env, ks)
    }

    _ -> {
      io.debug(statement)
      todo("not supported")
    }
  }
}

fn do_eval(exp, env, ks) {
  case exp {
    g.Int(raw) -> {
      let assert Ok(v) = int.parse(raw)
      apply(I(v), env, ks)
    }
    g.Float(raw) -> {
      let assert Ok(v) = float.parse(raw)
      apply(F(v), env, ks)
    }
    g.String(raw) -> apply(S(raw), env, ks)
    g.Variable(var) -> {
      case dict.get(env, var) {
        Ok(value) -> apply(value, env, ks)
        Error(Nil) -> Error(UndefinedVariable(var))
      }
    }
    // TODO rename Negate number
    g.NegateInt(exp) ->
      do_eval(exp, env, [Apply(Builtin(Arity1(negate_number)), [], []), ..ks])
    g.NegateBool(exp) ->
      do_eval(exp, env, [Apply(Builtin(Arity1(negate_bool)), [], []), ..ks])
    // Has to be at least one statement
    // exec block fn
    g.Block([statement, ..rest]) -> {
      let ks = case rest {
        [] -> ks
        _ -> [Continue(rest), ..ks]
      }
      do_exec(statement, env, ks)
    }
    g.Panic(message) -> Error(Panic(message))
    g.Todo(message) -> Error(Todo(message))
    g.Tuple([]) -> apply(T([]), env, ks)
    g.Tuple([first, ..elements]) ->
      do_eval(first, env, [BuildTuple(elements, []), ..ks])
    g.TupleIndex(exp, index) -> do_eval(exp, env, [AccessIndex(index), ..ks])
    g.List([], None) -> apply(L([]), env, ks)
    g.List([], Some(exp)) -> do_eval(exp, env, [Append([]), ..ks])
    g.List([first, ..elements], tail) ->
      do_eval(first, env, [BuildList(elements, [], tail), ..ks])
    g.Case([first, ..subjects], clauses) -> {
      let ks = [BuildSubjects(subjects, [], clauses), ..ks]
      do_eval(first, env, ks)
    }
    g.Fn(args, _annotation, body) -> apply(Closure(args, body, env), env, ks)
    g.FnCapture(None, f, left, right) -> {
      let ks = [CaptureArgs(left, right), ..ks]
      do_eval(f, env, ks)
    }
    // TODO real arguments
    // TODO handle labeled arguments
    g.Call(function, args) -> do_eval(function, env, [Args(args), ..ks])
    // g.BitString(segments) ->
    g.BinaryOperator(name, left, right) -> {
      let right = case name {
        g.Pipe ->
          case right {
            g.Call(f, args) -> g.FnCapture(None, f, [], args)
            g.FnCapture(_, _, _, _) -> right
            f -> g.FnCapture(None, f, [], [])
          }
        _ -> right
      }
      let impl = bin_impl(name)
      let value = Builtin(Arity2(impl))
      let ks = [Args([g.Field(None, left), g.Field(None, right)]), ..ks]
      apply(value, env, ks)
    }
    _ -> {
      io.debug(#("unsupported ", exp))
      todo("not supported")
    }
  }
}

// Think it makes sense to have bind/match in value.gleam
// with separate testing
// Whole effects proposal can be walk through here

fn assign_pattern(env, pattern, value) {
  case pattern, value {
    g.PatternDiscard(_name), _any -> Ok(env)
    g.PatternVariable(name), any -> Ok(dict.insert(env, name, any))
    g.PatternInt(i), I(expected) ->
      case int.to_string(expected) == i {
        True -> Ok(env)
        False -> Error(FailedAssignment(pattern, value))
      }
    g.PatternInt(_), unexpected -> Error(IncorrectTerm("Int", unexpected))
    g.PatternFloat(i), F(given) ->
      case float.to_string(given) == i {
        True -> Ok(env)
        False -> Error(FailedAssignment(pattern, value))
      }
    g.PatternFloat(_), unexpected -> Error(IncorrectTerm("Float", unexpected))
    g.PatternString(i), S(given) ->
      case given == i {
        True -> Ok(env)
        False -> Error(FailedAssignment(pattern, value))
      }
    g.PatternString(_), unexpected -> Error(IncorrectTerm("String", unexpected))
    g.PatternConcatenate(left, assignment), S(given) ->
      case string.split_once(given, left) {
        Ok(#("", rest)) ->
          case assignment {
            g.Discarded(_) -> Ok(env)
            g.Named(name) -> Ok(dict.insert(env, name, S(rest)))
          }
        Error(Nil) -> Error(FailedAssignment(pattern, value))
      }
    g.PatternConcatenate(_, _), unexpected ->
      Error(IncorrectTerm("String", unexpected))
    g.PatternTuple(patterns), T(elements) -> {
      case list.strict_zip(patterns, elements) {
        // TODO make a do match function
        Ok(pairs) ->
          list.try_fold(pairs, env, fn(env, pair) {
            let #(p, v) = pair
            assign_pattern(env, p, v)
          })
        Error(_) -> Error(FailedAssignment(pattern, value))
      }
    }
    g.PatternTuple(_), unexpected -> Error(IncorrectTerm("Tuple", unexpected))
    g.PatternList(patterns, tail), L(values) -> {
      use #(env, remaining) <- try(match_elements(env, patterns, values))
      case tail, remaining {
        Some(p), remaining -> assign_pattern(env, p, L(remaining))
        None, [] -> Ok(env)
        _, _ -> Error(IncorrectTerm("Empty list", L(remaining)))
      }
    }
    g.PatternList(patterns, tail), unexpected ->
      Error(IncorrectTerm("List", unexpected))
    // List zip with leftovrs
    g.PatternConstructor(None, constuctor, args, False), R(name, fields) -> {
      // TODO extend with module
      use env <- try(case constuctor == name {
        True ->
          case list.strict_zip(args, fields) {
            Ok(pairs) ->
              list.try_fold(pairs, env, fn(env, pair) {
                let #(g.Field(None, p), g.Field(None, value)) = pair
                assign_pattern(env, p, value)
              })
            Error(_) ->
              Error(IncorrectArity(list.length(args), list.length(fields)))
          }
        False -> Error(FailedAssignment(pattern, value))
      })
      Ok(env)
    }
    g.PatternConstructor(None, _, _, False), unexpected ->
      Error(IncorrectTerm("Custom Type", unexpected))
    g.PatternBitString(_segments), _ -> {
      io.debug(#("unsupported pat", pattern))
      panic
    }
    g.PatternAssignment(pattern, name), _ -> {
      use env <- try(assign_pattern(env, pattern, value))
      Ok(dict.insert(env, name, value))
    }
  }
}

// recursive because zipping does favor one over run.
// in this case too many elements is ok with tail but not too many patterns
fn match_elements(env, patterns, values) {
  case patterns, values {
    [], values -> Ok(#(env, values))
    [p, ..patterns], [v, ..values] -> {
      use env <- try(assign_pattern(env, p, v))
      match_elements(env, patterns, values)
    }
    [p, ..], [] -> Error(FailedAssignment(p, L([])))
  }
}

fn apply(value, env, ks) {
  case ks {
    [] -> Ok(value)
    [Assign(pattern), Continue([statement, ..rest]), ..ks] -> {
      let ks = case rest {
        [] -> ks
        _ -> [Continue(rest), ..ks]
      }
      use env <- try(assign_pattern(env, pattern, value))
      do_exec(statement, env, ks)
    }
    [Assign(pattern), ..ks] -> {
      use env <- try(assign_pattern(env, pattern, value))
      Error(Finished(env))
    }
    [Args([]), ..ks] -> {
      call(value, [], env, ks)
    }
    [Args([g.Field(None, exp), ..rest]), ..ks] -> {
      let rest = list.map(rest, fn(a: g.Field(_)) { a.item })
      let ks = [Apply(value, rest, []), ..ks]
      do_eval(exp, env, ks)
    }
    [Apply(func, remaining, evaluated), ..ks] -> {
      let evaluated = list.reverse([value, ..evaluated])
      case remaining {
        [] -> {
          call(func, evaluated, env, ks)
        }
        [exp, ..remaining] -> {
          let ks = [Apply(func, remaining, evaluated), ..ks]
          do_eval(exp, env, ks)
        }
      }
    }
    [CaptureArgs([first, ..before], after), ..ks] -> {
      let ks = [BuildBefore(value, before, [], after), ..ks]
      let g.Field(None, first) = first
      do_eval(first, env, ks)
    }
    [CaptureArgs([], [first, ..after]), ..ks] -> {
      let ks = [BuildAfter(value, [], after, []), ..ks]
      let g.Field(None, first) = first
      do_eval(first, env, ks)
    }
    [CaptureArgs([], []), ..ks] -> {
      // No need to create a capture value as unwrapped at call time
      apply(value, env, ks)
    }
    [BuildBefore(f, [first, ..expressions], values, after), ..ks] -> {
      let values = [value, ..values]
      let ks = [BuildBefore(f, expressions, values, after), ..ks]
      let g.Field(None, first) = first
      do_eval(first, env, ks)
    }
    [BuildBefore(f, [], values, after), ..ks] -> {
      let values = [value, ..values]
      case after {
        [] -> {
          let before = list.reverse(values)
          apply(Captured(f, before, []), env, ks)
        }
        [first, ..expressions] -> {
          let ks = [BuildAfter(f, values, expressions, []), ..ks]
          let g.Field(None, first) = first
          do_eval(first, env, ks)
        }
      }
    }
    [BuildAfter(f, before, [first, ..expressions], values), ..ks] -> {
      let values = [value, ..values]
      let ks = [BuildAfter(f, before, expressions, values), ..ks]
      let g.Field(None, first) = first
      do_eval(first, env, ks)
    }
    [BuildAfter(f, before, [], values), ..ks] -> {
      let before = list.reverse(before)
      let after = list.reverse([value, ..values])
      apply(Captured(f, before, after), env, ks)
    }

    [BuildTuple([], gathered), ..ks] ->
      apply(T(list.reverse([value, ..gathered])), env, ks)
    [BuildTuple([next, ..remaining], gathered), ..ks] ->
      do_eval(next, env, [BuildTuple(remaining, [value, ..gathered]), ..ks])
    [AccessIndex(index), ..ks] -> {
      use elements <- try(as_tuple(value))
      use element <- try(
        list.at(elements, index)
        |> result.replace_error(OutOfRange(list.length(elements), index)),
      )
      apply(element, env, ks)
    }
    [BuildList([], gathered, None), ..ks] ->
      apply(L(list.reverse([value, ..gathered])), env, ks)
    [BuildList([], gathered, Some(tail)), ..ks] ->
      do_eval(tail, env, [Append([value, ..gathered]), ..ks])
    [BuildList([next, ..remaining], gathered, tail), ..ks] ->
      do_eval(next, env, [BuildList(remaining, [value, ..gathered], tail), ..ks])
    [Append(gathered), ..ks] -> {
      use elements <- try(as_list(value))
      apply(L(list.append(list.reverse(gathered), elements)), env, ks)
    }
    // Should subjects also be non empty list
    [BuildSubjects([next, ..expressions], values, clauses), ..ks] -> {
      let ks = [BuildSubjects(expressions, [value, ..values], clauses), ..ks]
      do_eval(next, env, ks)
    }

    // TODO caring about modlue to match on.
    // TODO testing on guards
    [BuildSubjects([], values, clauses), ..ks] -> {
      let values = list.reverse([value, ..values])
      list.find_map(clauses, fn(clause) {
        list.find_map(clause.patterns, fn(patterns) {
          use bindings <- try(
            list.strict_zip(patterns, values)
            |> result.replace_error(IncorrectArity(
              list.length(patterns),
              list.length(values),
            )),
          )
          use env <- try(
            list.try_fold(bindings, env, fn(env, binding) {
              let #(pattern, value) = binding
              assign_pattern(env, pattern, value)
            }),
          )
          do_eval(clause.body, env, ks)
        })
      })
      // TODO think about having proper error from inside match
      |> result.replace_error(NoMatch(values))
    }
    [Continue([statement, ..rest]), ..ks] -> {
      let ks = case rest {
        [] -> ks
        _ -> [Continue(rest), ..ks]
      }
      do_exec(statement, env, ks)
    }
    _ -> {
      io.debug(#(value, ks, "---------"))
      todo("bad apply")
    }
  }
}

fn call(func, args, env, ks) {
  case func, args {
    Closure(params, [body], captured), args -> {
      // as long as closure keeps returning itself until full of arguments
      let names =
        list.map(params, fn(p: g.FnParameter) {
          case p.name {
            g.Named(name) -> name
          }
        })
      case list.strict_zip(names, args) {
        Ok(entries) -> {
          let env =
            list.fold(entries, env, fn(acc, new) {
              let #(k, value) = new
              dict.insert(acc, k, value)
            })
          do_exec(body, env, ks)
        }
        // TODO why is this not Nil or with values
        Error(list.LengthMismatch) ->
          Error(IncorrectArity(list.length(names), list.length(args)))
      }
    }
    Captured(f, left, right), args -> {
      let assert [arg] = args
      let args = list.flatten([left, [arg], right])
      call(f, args, env, ks)
    }
    Builtin(Arity1(impl)), [a] -> {
      impl(a, env, ks)
    }
    Builtin(Arity2(impl)), [a, b] -> {
      impl(a, b, env, ks)
    }
    other, _ -> Error(NotAFunction(other))
  }
}

fn negate_number(in, env, ks) {
  case in {
    I(v) -> Ok(I(-v))
    F(v) -> Ok(F(-1.0 *. v))
    _ -> Error(IncorrectTerm("Integer or Float", in))
  }
}

fn negate_bool(in, env, ks) {
  use in <- try(as_boolean(in))
  Ok(from_bool(!in))
}

fn bin_impl(name) {
  case name {
    g.And -> fn(a, b, env, ks) {
      use a <- try(as_boolean(a))
      use b <- try(as_boolean(b))
      apply(from_bool(a && b), env, ks)
    }
    g.Or -> fn(a, b, env, ks) {
      use a <- try(as_boolean(a))
      use b <- try(as_boolean(b))
      apply(from_bool(a || b), env, ks)
    }
    g.Eq -> fn(a, b, env, ks) { apply(from_bool(a == b), env, ks) }
    g.NotEq -> fn(a, b, env, ks) { apply(from_bool(a != b), env, ks) }
    g.LtInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(from_bool(a < b), env, ks)
    }
    g.LtEqInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(from_bool(a <= b), env, ks)
    }
    g.LtFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(from_bool(a <. b), env, ks)
    }
    g.LtEqFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(from_bool(a <=. b), env, ks)
    }
    g.GtEqInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(from_bool(a >= b), env, ks)
    }
    g.GtInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(from_bool(a > b), env, ks)
    }
    g.GtEqFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(from_bool(a >=. b), env, ks)
    }
    g.GtFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(from_bool(a >. b), env, ks)
    }
    g.Pipe -> fn(passed, f, env, ks) { call(f, [passed], env, ks) }
    g.AddInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(I(a + b), env, ks)
    }
    g.AddFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(F(a +. b), env, ks)
    }
    g.SubInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(I(a - b), env, ks)
    }
    g.SubFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(F(a -. b), env, ks)
    }
    g.MultInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(I(a * b), env, ks)
    }
    g.MultFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(F(a *. b), env, ks)
    }
    g.DivInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(I(a / b), env, ks)
    }
    g.DivFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(F(a /. b), env, ks)
    }
    g.RemainderInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(I(a % b), env, ks)
    }
    g.Concatenate -> fn(a, b, env, ks) {
      use a <- try(as_string(a))
      use b <- try(as_string(b))
      apply(S(a <> b), env, ks)
    }
  }
}

fn as_integer(value) {
  case value {
    I(value) -> Ok(value)
    _ -> Error(IncorrectTerm("Integer", value))
  }
}

fn as_float(value) {
  case value {
    F(value) -> Ok(value)
    _ -> Error(IncorrectTerm("Float", value))
  }
}

fn as_boolean(value) {
  case value {
    R("True", []) -> Ok(True)
    R("False", []) -> Ok(False)
    _ -> Error(IncorrectTerm("Boolean", value))
  }
}

fn from_bool(raw) {
  case raw {
    True -> R("True", [])
    False -> R("False", [])
  }
}

fn as_string(value) {
  case value {
    S(value) -> Ok(value)
    _ -> Error(IncorrectTerm("String", value))
  }
}

fn as_tuple(value) {
  case value {
    T(elements) -> Ok(elements)
    _ -> Error(IncorrectTerm("Tuple", value))
  }
}

fn as_list(value) {
  case value {
    L(elements) -> Ok(elements)
    _ -> Error(IncorrectTerm("List", value))
  }
}

type Env =
  dict.Dict(String, Value)

pub type K {
  Assign(pattern: g.Pattern)
  Apply(
    function: Value,
    expressions: List(g.Expression),
    evaluated: List(Value),
  )
  Args(List(g.Field(g.Expression)))
  CaptureArgs(
    before: List(g.Field(g.Expression)),
    after: List(g.Field(g.Expression)),
  )
  BuildBefore(
    function: Value,
    expressions: List(g.Field(g.Expression)),
    values: List(Value),
    after: List(g.Field(g.Expression)),
  )
  BuildAfter(
    function: Value,
    befor: List(Value),
    expressions: List(g.Field(g.Expression)),
    values: List(Value),
  )
  BuildTuple(expressions: List(g.Expression), values: List(Value))
  AccessIndex(Int)
  BuildList(
    expressions: List(g.Expression),
    values: List(Value),
    tail: Option(g.Expression),
  )
  Append(values: List(Value))
  BuildSubjects(
    expressions: List(g.Expression),
    values: List(Value),
    clauses: List(g.Clause),
  )
  Continue(List(g.Statement))
}
