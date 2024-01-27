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
import repl/reader

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

pub type State =
  #(Dict(String, Value), Dict(String, g.Module))

pub fn init(scope, modules) {
  #(scope, modules)
}

// could return bindings not env
pub fn read(term, state) {
  let #(scope, modules) = state
  case term {
    reader.Import(module, binding, unqualified) -> {
      case dict.get(modules, module) {
        Ok(module) -> {
          let scope = dict.insert(scope, binding, Module(module))
          let scope =
            list.fold(unqualified, scope, fn(scope, extra) {
              let #(field, name) = extra
              let assert Ok(value) = access_module(module, field)
              dict.insert(scope, name, value)
            })
          Ok(#(None, #(scope, modules)))
        }
        Error(Nil) -> {
          Error(UnknownModule(module))
        }
      }
    }
    reader.CustomType(variants) -> {
      let scope =
        list.fold(variants, scope, fn(scope, variant) {
          let #(name, fields) = variant
          let value = case fields {
            [] -> R(name, [])
            _ -> Constructor(name, fields)
          }
          dict.insert(scope, name, value)
        })
      let state = #(scope, modules)
      Ok(#(None, state))
    }
    reader.Function(name, parameters, body) -> {
      let value = ClosureLabeled(parameters, body, scope)
      let scope = dict.insert(scope, name, value)
      let state = #(scope, modules)
      Ok(#(Some(value), state))
    }
    reader.Statements(statements) -> {
      case exec(statements, scope) {
        Ok(value) -> Ok(#(Some(value), state))
        Error(Finished(scope)) -> {
          let state = #(scope, modules)
          Ok(#(None, state))
        }
        Error(reason) -> Error(reason)
      }
    }
    _ -> {
      io.debug(term)
      panic as "not suppred in read"
    }
  }
}

pub type Value {
  I(Int)
  F(Float)
  S(String)
  T(List(Value))
  L(List(Value))
  R(String, List(g.Field(Value)))
  Constructor(String, List(Option(String)))
  Closure(List(g.FnParameter), List(g.Statement), Env)
  // this will be module env
  ClosureLabeled(List(g.FunctionParameter), List(g.Statement), Env)
  Captured(function: Value, before: List(Value), after: List(Value))
  Builtin(Arity)
  Module(g.Module)
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
  UnknownModule(String)
}

// pub fn module(src) {
//   // TODO update env with imports
//   use mod <- try(g.module(src))
//   let fns =
//     list.map(mod.functions, fn(definition) {
//       let g.Definition([], f) = definition
//       #(f.name, ClosureLabeled(f.parameters, f.body, dict.new()))
//     })

//   Ok(Module(dict.from_list(fns)))
// }

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
      do_eval(exp, env, [
        Apply(Builtin(Arity1(negate_number)), None, [], []),
        ..ks
      ])
    g.NegateBool(exp) ->
      do_eval(exp, env, [
        Apply(Builtin(Arity1(negate_bool)), None, [], []),
        ..ks
      ])
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
    g.FieldAccess(container, label) ->
      do_eval(container, env, [Access(label), ..ks])
    // g.RecordUpdate(mod, constructor, original, [#(label, exp), ..rest]) -> {
    //   let assert R("", fields) = original
    //   let ks = [Update(constructor, fields, label, rest, []), ..ks]
    //   do_eval(exp, env, ks)
    // }
    g.RecordUpdate(mod, constructor, exp, fields) -> {
      do_eval(exp, env, [RecordUpdate(mod, constructor, fields), ..ks])
    }
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
      todo as "not supported"
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
    [Args([g.Field(label, exp), ..rest]), ..ks] -> {
      let ks = [Apply(value, label, rest, []), ..ks]
      do_eval(exp, env, ks)
    }
    [Apply(func, label, remaining, evaluated), ..ks] -> {
      let evaluated = list.reverse([g.Field(label, value), ..evaluated])
      case remaining {
        [] -> {
          call(func, evaluated, env, ks)
        }
        [g.Field(label, exp), ..remaining] -> {
          let ks = [Apply(func, label, remaining, evaluated), ..ks]
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
    [Access(field), ..ks] -> {
      let assert Module(module) = value
      use value <- try(access_module(module, field))
      apply(value, env, ks)
    }
    [RecordUpdate(module, constructor, updates), ..ks] -> {
      use original <- try(case value {
        // TODO module match
        R(c, fields) if c == constructor -> Ok(fields)
      })
      // _ -> Error(IncorrectTerm(constructor,value))
      case updates {
        [#(label, exp), ..updates] -> {
          let ks = [Update(constructor, original, label, updates), ..ks]
          do_eval(exp, env, ks)
        }
        [] -> todo as "done update"
      }
    }
    [Update(constructor, current, label, updates), ..ks] -> {
      // This doesn't error if one is misisng
      let current =
        list.map(current, fn(field) {
          case field {
            g.Field(Some(k), _old) if k == label -> g.Field(Some(k), value)
            _ -> field
          }
        })
      case updates {
        [] -> apply(R(constructor, current), env, ks)
        [#(label, exp), ..updates] -> {
          let ks = [Update(constructor, current, label, updates), ..ks]
          do_eval(exp, env, ks)
        }
      }
    }
    // Should subjects also be non empty list
    [BuildSubjects([next, ..expressions], values, clauses), ..ks] -> {
      let ks = [BuildSubjects(expressions, [value, ..values], clauses), ..ks]
      do_eval(next, env, ks)
    }

    // TODO caring about module to match on.
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
      todo as "bad apply"
    }
  }
}

fn access_module(module: g.Module, field) {
  let functions =
    list.map(module.functions, fn(f) {
      let g.Definition(
        _,
        g.Function(
          name: name,
          publicity: public,
          parameters: parameters,
          body: body,
          ..,
        ),
      ) = f
      // TODO not empty env,probably module
      #(name, ClosureLabeled(parameters, body, dict.new()))
    })
  case list.key_find(functions, field) {
    Ok(value) -> Ok(value)
    // TODO need to be careful for public and not when in module
    Error(Nil) -> {
      let constructors =
        list.flat_map(module.custom_types, fn(definition) {
          let g.Definition(_, g.CustomType(variants: variants, ..)) = definition
          list.map(variants, fn(v) {
            let g.Variant(name, fields) = v
            let labels = list.map(fields, fn(f: g.Field(_)) { f.label })
            #(name, Constructor(name, labels))
          })
        })
      // |> io.debug()
      case list.key_find(constructors, field) {
        Ok(value) -> Ok(value)
      }
    }
  }
}

fn do_pop_parameter(params, label: String, acc) {
  case params {
    [] -> Error(MissingField(label))
    [g.FunctionParameter(Some(l), name, _type), ..params] if l == label ->
      Ok(#(name, list.append(list.reverse(acc), params)))
    [param, ..params] -> do_pop_parameter(params, label, [param, ..acc])
  }
}

fn pop_parameter(params, label) {
  do_pop_parameter(params, label, [])
}

// TODO return unmatched params because we need that for record
// do_pair_args returns empty incorrect arity that is fixed
fn pair_args(params: List(g.FunctionParameter), args: List(g.Field(Value)), env) {
  case args {
    [g.Field(None, value), ..args] -> {
      case params {
        // [g.Field(_, g.Discarded(_)), ..params] -> pair_args(params, args, [])
        [g.FunctionParameter(_, name, _type), ..params] -> {
          let env = case name {
            g.Named(name) -> [#(name, value), ..env]
            g.Discarded(_) -> env
          }
          pair_args(params, args, env)
        }
        [] -> Error(IncorrectArity(0, 0))
      }
    }
    [g.Field(Some(label), value), ..args] -> {
      use #(name, params) <- try(pop_parameter(params, label))
      let env = case name {
        g.Named(name) -> [#(name, value), ..env]
        g.Discarded(_) -> env
      }
      pair_args(params, args, env)
    }
    [] -> Ok(#(list.reverse(env), params))
  }
}

fn call(func, args, env, ks) {
  case func, args {
    // TODO test multistatement body
    Closure(params, body, captured), args -> {
      // as long as closure keeps returning itself until full of arguments
      let names =
        list.map(params, fn(p: g.FnParameter) {
          case p.name {
            g.Named(name) -> Some(name)
            g.Discarded(_) -> None
          }
        })
      case list.strict_zip(names, args) {
        Ok(entries) -> {
          use env <- try(
            list.try_fold(entries, env, fn(acc, new) {
              // can't have named fields here
              case new {
                #(k, g.Field(None, value)) -> {
                  let env = case k {
                    None -> env
                    Some(k) -> dict.insert(acc, k, value)
                  }
                  Ok(env)
                }

                #(_k, g.Field(Some(label), _value)) ->
                  Error(MissingField(label))
              }
            }),
          )
          let [statement, ..rest] = body
          let ks = case rest {
            [] -> ks
            rest -> [Continue(rest), ..ks]
          }
          do_exec(statement, env, ks)
        }
        // TODO why is this not Nil or with values
        Error(list.LengthMismatch) ->
          Error(IncorrectArity(list.length(names), list.length(args)))
      }
    }
    // CAn we always use function parameters
    ClosureLabeled(params, body, captures), args -> {
      // TODO deduplicate with args above but need to add label handling
      case pair_args(params, args, []) {
        Ok(#(bindings, [])) -> {
          let env =
            list.fold(bindings, env, fn(env, new: #(_, _)) {
              dict.insert(env, new.0, new.1)
            })
          let [statement, ..rest] = body
          let ks = case rest {
            [] -> []
            rest -> [Continue(rest), ..ks]
          }
          do_exec(statement, env, ks)
        }
        Ok(#(_, _remaining)) ->
          Error(IncorrectArity(list.length(params), list.length(args)))
        // Looses size information in pairing
        Error(IncorrectArity(0, 0)) ->
          Error(IncorrectArity(list.length(params), list.length(args)))

        Error(reason) -> Error(reason)
      }
      // Error(IncorrectArity(list.length(names), list.length(args)))
    }
    Captured(f, left, right), args -> {
      // is named args supported for capture
      let assert [g.Field(None, arg)] = args
      let args =
        list.flatten([left, [arg], right])
        |> list.map(g.Field(None, _))
      call(f, args, env, ks)
    }
    // All unlabelled must go first
    Constructor(name, fields), args -> {
      case constuct_fields(fields, args, []) {
        Ok(fields) -> apply(R(name, fields), env, ks)
        Error(IncorrectArity(_, _)) ->
          Error(IncorrectArity(list.length(fields), list.length(args)))
        Error(reason) -> Error(reason)
      }
    }
    Builtin(Arity1(impl)), [a] -> {
      let assert g.Field(None, a) = a
      impl(a, env, ks)
    }
    Builtin(Arity2(impl)), [a, b] -> {
      let assert g.Field(None, a) = a
      let assert g.Field(None, b) = b
      impl(a, b, env, ks)
    }
    other, _ -> Error(NotAFunction(other))
  }
}

fn constuct_fields(fields, args, acc) {
  case args, fields {
    [], [] -> Ok(list.reverse(acc))
    [g.Field(None, value), ..args], [field, ..fields] -> {
      let acc = [g.Field(field, value), ..acc]
      constuct_fields(fields, args, acc)
    }
    // go through in field order
    [g.Field(Some(for_error), _), ..], [Some(label), ..fields] -> {
      case pop_field(args, label, []) {
        Ok(#(value, args)) -> {
          let acc = [g.Field(Some(label), value), ..acc]
          constuct_fields(fields, args, acc)
        }
        Error(Nil) -> Error(MissingField(for_error))
      }
    }
    _, _ -> Error(IncorrectArity(0, 0))
  }
}

fn pop_field(fields, label, acc) {
  case fields {
    [g.Field(Some(l), value), ..rest] if l == label ->
      Ok(#(value, list.append(list.reverse(acc), rest)))
    [popped, ..fields] -> pop_field(fields, label, [popped, ..acc])
    [] -> Error(Nil)
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
    g.Pipe -> fn(passed, f, env, ks) {
      call(f, [g.Field(None, passed)], env, ks)
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
    label: Option(String),
    expressions: List(g.Field(g.Expression)),
    evaluated: List(g.Field(Value)),
  )
  RecordUpdate(
    module: Option(String),
    constructor: String,
    fields: List(#(String, g.Expression)),
  )
  Update(
    // module: Option(String)
    constuctor: String,
    original: List(g.Field(Value)),
    current: String,
    expressions: List(#(String, g.Expression)),
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
  Access(field: String)
  Append(values: List(Value))
  BuildSubjects(
    expressions: List(g.Expression),
    values: List(Value),
    clauses: List(g.Clause),
  )
  Continue(List(g.Statement))
}
