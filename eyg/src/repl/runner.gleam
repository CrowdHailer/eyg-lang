import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import glance as g

// move to reason.gleam after moving out value.gleam
pub type Reason {
  NotAFunction(Value)
  IncorrectArity(expected: Int, given: Int)
  UndefinedVariable(String)
  Panic(message: Option(String))
  Todo(message: Option(String))
  OutOfRange(size: Int, given: Int)
  NoMatch(term: Value)
  IncorrectTerm(expected: String, got: Value)
  MissingField(String)
  Finished(Dict(String, Value))
}

// glance parses statements assuming a block
pub fn statements(acc, tokens) {
  case g.statement(tokens) {
    Ok(#(statement, rest)) -> {
      let acc = [statement, ..acc]
      case rest {
        [] -> Ok(#(list.reverse(acc), Nil, Nil))
        _ -> statements(acc, rest)
      }
    }
    Error(reason) -> Error(reason)
  }
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
    g.Assignment(g.Let, pattern, _annotation, exp) -> {
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
    // Why are these not their own type
    g.Variable("True") -> apply(B(True), env, ks)
    g.Variable("False") -> apply(B(False), env, ks)
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
    // g.List()
    g.Fn(args, _annotation, body) -> apply(Closure(args, body, env), env, ks)
    g.FnCapture(None, f, left, right) -> {
      let ks = [CaptureArgs(left, right), ..ks]
      do_eval(f, env, ks)
    }
    // TODO real arguments
    // TODO handle labeled arguments
    g.Call(function, args) -> do_eval(function, env, [Args(args), ..ks])
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

fn apply(value, env, ks) {
  case ks {
    [] -> Ok(value)
    [Assign(pattern), Continue([statement, ..rest]), ..ks] -> {
      let ks = case rest {
        [] -> ks
        _ -> [Continue(rest), ..ks]
      }
      let env = case pattern {
        g.PatternVariable(name) -> {
          dict.insert(env, name, value)
        }
      }
      do_exec(statement, env, ks)
    }
    [Assign(pattern), ..ks] -> {
      let env = case pattern {
        g.PatternVariable(name) -> {
          dict.insert(env, name, value)
        }
      }
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
  Ok(B(!in))
}

fn bin_impl(name) {
  case name {
    g.And -> fn(a, b, env, ks) {
      use a <- try(as_boolean(a))
      use b <- try(as_boolean(b))
      apply(B(a && b), env, ks)
    }
    g.Or -> fn(a, b, env, ks) {
      use a <- try(as_boolean(a))
      use b <- try(as_boolean(b))
      apply(B(a || b), env, ks)
    }
    g.Eq -> fn(a, b, env, ks) { apply(B(a == b), env, ks) }
    g.NotEq -> fn(a, b, env, ks) { apply(B(a != b), env, ks) }
    g.LtInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(B(a < b), env, ks)
    }
    g.LtEqInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(B(a <= b), env, ks)
    }
    g.LtFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(B(a <. b), env, ks)
    }
    g.LtEqFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(B(a <=. b), env, ks)
    }
    g.GtEqInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(B(a >= b), env, ks)
    }
    g.GtInt -> fn(a, b, env, ks) {
      use a <- try(as_integer(a))
      use b <- try(as_integer(b))
      apply(B(a > b), env, ks)
    }
    g.GtEqFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(B(a >=. b), env, ks)
    }
    g.GtFloat -> fn(a, b, env, ks) {
      use a <- try(as_float(a))
      use b <- try(as_float(b))
      apply(B(a >. b), env, ks)
    }
    g.Pipe -> fn(passed, f, env, ks) {
      io.debug(f)
      call(f, [passed], env, ks)
    }
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
    B(value) -> Ok(value)
    _ -> Error(IncorrectTerm("Boolean", value))
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

pub type Value {
  I(Int)
  F(Float)
  B(Bool)
  S(String)
  T(List(Value))
  L(List(Value))
  Closure(List(g.FnParameter), List(g.Statement), Env)
  Captured(function: Value, before: List(Value), after: List(Value))
  Builtin(Arity)
}

pub type Arity {
  TupleConstructor(size: Int, gathered: List(Value))
  Arity1(fn(Value, Env, List(K)) -> Result(Value, Reason))
  Arity2(fn(Value, Value, Env, List(K)) -> Result(Value, Reason))
}

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
  Continue(List(g.Statement))
}
