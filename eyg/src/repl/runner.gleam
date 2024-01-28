import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{try}
import gleam/string
import glance as g
import scintilla/value.{type Value} as v
import scintilla/reason as r
import scintilla/cast
import repl/reader

pub fn prelude() {
  // todo module for prelude namespacing
  dict.from_list([
    #("Nil", v.R("Nil", [])),
    #("True", v.R("True", [])),
    #("False", v.R("False", [])),
    #("Ok", v.Constructor("Ok", [None])),
    #("Error", v.Constructor("Error", [None])),
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
          let scope = dict.insert(scope, binding, v.Module(module))
          let scope =
            list.fold(unqualified, scope, fn(scope, extra) {
              let #(field, name) = extra
              let assert Ok(value) = access_module(module, field)
              dict.insert(scope, name, value)
            })
          Ok(#(None, #(scope, modules)))
        }
        Error(Nil) -> {
          Error(r.UnknownModule(module))
        }
      }
    }
    reader.CustomType(variants) -> {
      let scope =
        list.fold(variants, scope, fn(scope, variant) {
          let #(name, fields) = variant
          let value = case fields {
            [] -> v.R(name, [])
            _ -> v.Constructor(name, fields)
          }
          dict.insert(scope, name, value)
        })
      let state = #(scope, modules)
      Ok(#(None, state))
    }
    reader.Constant(name, exp) -> {
      case loop(next(eval(exp, scope, []))) {
        Ok(value) -> {
          let scope = dict.insert(scope, name, value)
          let state = #(scope, modules)
          Ok(#(Some(value), state))
        }
        Error(#(reason, _, _)) -> Error(reason)
      }
    }
    reader.Function(name, parameters, body) -> {
      let value = v.NamedClosure(parameters, body, scope)
      let scope = dict.insert(scope, name, value)
      let state = #(scope, modules)
      Ok(#(Some(value), state))
    }
    reader.Statements(statements) -> {
      case exec(statements, scope) {
        Ok(value) -> Ok(#(Some(value), state))
        Error(r.Finished(scope)) -> {
          let state = #(scope, modules)
          Ok(#(None, state))
        }
        Error(reason) -> Error(reason)
      }
    }
  }
}

pub fn exec(statements: List(g.Statement), env) {
  let [statement, ..rest] = statements
  let ks = case rest {
    [] -> []
    rest -> [Continue(rest)]
  }
  do_exec(statement, env, ks)
}

fn do_exec(statement, env, ks) {
  case statement {
    g.Expression(exp) -> loop(next(eval(exp, env, ks)))
    // We do the same
    g.Assignment(_kind, pattern, _annotation, exp) -> {
      let ks = [Assign(pattern), ..ks]
      loop(next(eval(exp, env, ks)))
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
      loop(next(eval(exp, env, ks)))
    }
  }
  |> result.map_error(fn(e: #(_, _, _)) { e.0 })
}

// TODO remove to runner
pub fn loop(next) {
  case next {
    Loop(c, e, k) -> loop(step(c, e, k))
    Break(result) -> result
  }
}

pub type Control {
  E(g.Expression)
  V(Value)
}

pub type Scope =
  Dict(String, Value)

pub type Next {
  Loop(Control, Scope, List(K))
  Break(Result(Value, #(r.Reason, Scope, List(K))))
}

pub fn step(c, env, ks) {
  case c, ks {
    E(exp), ks -> next(eval(exp, env, ks))
    V(value), [] -> Break(Ok(value))
    V(value), [k, ..rest] -> next(apply(value, env, k, rest))
  }
}

pub fn next(return) {
  case return {
    Ok(#(c, e, k)) -> Loop(c, e, k)
    Error(info) -> Break(Error(info))
  }
}

fn push_statements(statements, env, ks) {
  // Has to be at least one statement
  let assert [statement, ..rest] = statements
  let ks = case rest {
    [] -> ks
    _ -> [Continue(rest), ..ks]
  }
  case statement {
    g.Expression(exp) -> Ok(#(E(exp), env, ks))
    g.Assignment(_kind, pattern, _annotation, exp) -> {
      let ks = [Assign(pattern), ..ks]
      Ok(#(E(exp), env, ks))
    }
  }
}

fn eval(exp, env, ks) {
  case exp {
    g.Int(raw) -> {
      let assert Ok(v) = int.parse(raw)
      Ok(#(V(v.I(v)), env, ks))
    }
    g.Float(raw) -> {
      let assert Ok(v) = float.parse(raw)
      Ok(#(V(v.F(v)), env, ks))
    }
    g.String(raw) -> Ok(#(V(v.S(raw)), env, ks))
    g.Variable(var) -> {
      case dict.get(env, var) {
        Ok(value) -> Ok(#(V(value), env, ks))
        Error(Nil) -> Error(r.UndefinedVariable(var))
      }
    }
    g.NegateInt(exp) ->
      Ok(#(E(exp), env, [Apply(v.NegateInt, None, [], []), ..ks]))
    g.NegateBool(exp) ->
      Ok(#(E(exp), env, [Apply(v.NegateBool, None, [], []), ..ks]))
    g.Block(statements) -> push_statements(statements, env, ks)
    g.Panic(message) -> Error(r.Panic(message))
    g.Todo(message) -> Error(r.Todo(message))
    g.Tuple([]) -> Ok(#(V(v.T([])), env, ks))
    g.Tuple([first, ..elements]) ->
      Ok(#(E(first), env, [BuildTuple(elements, []), ..ks]))
    g.TupleIndex(exp, index) -> Ok(#(E(exp), env, [AccessIndex(index), ..ks]))
    g.List([], None) -> Ok(#(V(v.L([])), env, ks))
    g.List([], Some(exp)) -> Ok(#(E(exp), env, [Append([]), ..ks]))
    g.List([first, ..elements], tail) ->
      Ok(#(E(first), env, [BuildList(elements, [], tail), ..ks]))
    g.FieldAccess(container, label) ->
      Ok(#(E(container), env, [Access(label), ..ks]))
    g.RecordUpdate(mod, constructor, exp, fields) -> {
      Ok(#(E(exp), env, [RecordUpdate(mod, constructor, fields), ..ks]))
    }
    g.Case([first, ..subjects], clauses) -> {
      let ks = [BuildSubjects(subjects, [], clauses), ..ks]
      Ok(#(E(first), env, ks))
    }
    g.Fn(args, _annotation, body) ->
      Ok(#(V(v.Closure(args, body, env)), env, ks))
    g.FnCapture(None, f, left, right) -> {
      let ks = [CaptureArgs(left, right), ..ks]
      Ok(#(E(f), env, ks))
    }
    g.Call(function, args) -> Ok(#(E(function), env, [Args(args), ..ks]))
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
      let value = v.BinaryOperator(name)
      let ks = [Args([g.Field(None, left), g.Field(None, right)]), ..ks]
      Ok(#(V(value), env, ks))
    }
    _ -> {
      io.debug(#("unsupported ", exp))
      todo as "not supported"
    }
  }
  |> result.map_error(fn(reason) { #(reason, env, ks) })
}

// Think it makes sense to have bind/match in value.gleam
// with separate testing
// Whole effects proposal can be walk through here

fn assign_pattern(env, pattern, value) {
  case pattern, value {
    g.PatternDiscard(_name), _any -> Ok(env)
    g.PatternVariable(name), any -> Ok(dict.insert(env, name, any))
    g.PatternInt(i), v.I(expected) ->
      case int.to_string(expected) == i {
        True -> Ok(env)
        False -> Error(r.FailedAssignment(pattern, value))
      }
    g.PatternInt(_), unexpected -> Error(r.IncorrectTerm("Int", unexpected))
    g.PatternFloat(i), v.F(given) ->
      case float.to_string(given) == i {
        True -> Ok(env)
        False -> Error(r.FailedAssignment(pattern, value))
      }
    g.PatternFloat(_), unexpected -> Error(r.IncorrectTerm("Float", unexpected))
    g.PatternString(i), v.S(given) ->
      case given == i {
        True -> Ok(env)
        False -> Error(r.FailedAssignment(pattern, value))
      }
    g.PatternString(_), unexpected ->
      Error(r.IncorrectTerm("String", unexpected))
    g.PatternConcatenate(left, assignment), v.S(given) ->
      case string.split_once(given, left) {
        Ok(#("", rest)) ->
          case assignment {
            g.Discarded(_) -> Ok(env)
            g.Named(name) -> Ok(dict.insert(env, name, v.S(rest)))
          }
        Error(Nil) -> Error(r.FailedAssignment(pattern, value))
      }
    g.PatternConcatenate(_, _), unexpected ->
      Error(r.IncorrectTerm("String", unexpected))
    g.PatternTuple(patterns), v.T(elements) -> {
      case list.strict_zip(patterns, elements) {
        // TODO make a do match function
        Ok(pairs) ->
          list.try_fold(pairs, env, fn(env, pair) {
            let #(p, v) = pair
            assign_pattern(env, p, v)
          })
        Error(_) -> Error(r.FailedAssignment(pattern, value))
      }
    }
    g.PatternTuple(_), unexpected -> Error(r.IncorrectTerm("Tuple", unexpected))
    g.PatternList(patterns, tail), v.L(values) -> {
      use #(env, remaining) <- try(match_elements(env, patterns, values))
      case tail, remaining {
        Some(p), remaining -> assign_pattern(env, p, v.L(remaining))
        None, [] -> Ok(env)
        _, _ -> Error(r.IncorrectTerm("Empty list", v.L(remaining)))
      }
    }
    g.PatternList(patterns, tail), unexpected ->
      Error(r.IncorrectTerm("List", unexpected))
    // List zip with leftovrs
    g.PatternConstructor(None, constuctor, args, False), v.R(name, fields) -> {
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
              Error(r.IncorrectArity(list.length(args), list.length(fields)))
          }
        False -> Error(r.FailedAssignment(pattern, value))
      })
      Ok(env)
    }
    g.PatternConstructor(None, _, _, False), unexpected ->
      Error(r.IncorrectTerm("Custom Type", unexpected))
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
    [p, ..], [] -> Error(r.FailedAssignment(p, v.L([])))
  }
}

fn apply(value, env, k, ks) {
  case k {
    Assign(pattern) -> {
      use env <- try(assign_pattern(env, pattern, value))
      case ks {
        [Continue(statements), ..ks] -> push_statements(statements, env, ks)
        [] -> Error(r.Finished(env))
      }
    }
    Args([]) -> {
      call(value, [], env, ks)
    }
    Args([g.Field(label, exp), ..rest]) -> {
      let ks = [Apply(value, label, rest, []), ..ks]
      Ok(#(E(exp), env, ks))
    }
    Apply(func, label, remaining, evaluated) -> {
      let evaluated = list.reverse([g.Field(label, value), ..evaluated])
      case remaining {
        [] -> {
          call(func, evaluated, env, ks)
        }
        [g.Field(label, exp), ..remaining] -> {
          let ks = [Apply(func, label, remaining, evaluated), ..ks]
          Ok(#(E(exp), env, ks))
        }
      }
    }
    CaptureArgs([first, ..before], after) -> {
      let ks = [BuildBefore(value, before, [], after), ..ks]
      let g.Field(None, first) = first
      Ok(#(E(first), env, ks))
    }
    CaptureArgs([], [first, ..after]) -> {
      let ks = [BuildAfter(value, [], after, []), ..ks]
      let g.Field(None, first) = first
      Ok(#(E(first), env, ks))
    }
    CaptureArgs([], []) -> {
      // No need to create a capture value as unwrapped at call time
      Ok(#(V(value), env, ks))
    }
    BuildBefore(f, [first, ..expressions], values, after) -> {
      let values = [value, ..values]
      let ks = [BuildBefore(f, expressions, values, after), ..ks]
      let g.Field(None, first) = first
      Ok(#(E(first), env, ks))
    }
    BuildBefore(f, [], values, after) -> {
      let values = [value, ..values]
      case after {
        [] -> {
          let before = list.reverse(values)
          Ok(#(V(v.Captured(f, before, [])), env, ks))
        }
        [first, ..expressions] -> {
          let ks = [BuildAfter(f, values, expressions, []), ..ks]
          let g.Field(None, first) = first
          Ok(#(E(first), env, ks))
        }
      }
    }
    BuildAfter(f, before, [first, ..expressions], values) -> {
      let values = [value, ..values]
      let ks = [BuildAfter(f, before, expressions, values), ..ks]
      let g.Field(None, first) = first
      Ok(#(E(first), env, ks))
    }
    BuildAfter(f, before, [], values) -> {
      let before = list.reverse(before)
      let after = list.reverse([value, ..values])
      Ok(#(V(v.Captured(f, before, after)), env, ks))
    }

    BuildTuple([], gathered) ->
      Ok(#(V(v.T(list.reverse([value, ..gathered]))), env, ks))
    BuildTuple([next, ..remaining], gathered) ->
      Ok(#(E(next), env, [BuildTuple(remaining, [value, ..gathered]), ..ks]))
    AccessIndex(index) -> {
      use elements <- try(cast.as_tuple(value))
      use element <- try(
        list.at(elements, index)
        |> result.replace_error(r.OutOfRange(list.length(elements), index)),
      )
      Ok(#(V(element), env, ks))
    }
    BuildList([], gathered, None) ->
      Ok(#(V(v.L(list.reverse([value, ..gathered]))), env, ks))
    BuildList([], gathered, Some(tail)) ->
      Ok(#(E(tail), env, [Append([value, ..gathered]), ..ks]))
    BuildList([next, ..remaining], gathered, tail) ->
      Ok(
        #(E(next), env, [BuildList(remaining, [value, ..gathered], tail), ..ks]),
      )
    Append(gathered) -> {
      use elements <- try(cast.as_list(value))
      Ok(#(V(v.L(list.append(list.reverse(gathered), elements))), env, ks))
    }
    Access(field) -> {
      use value <- try(case value {
        v.Module(module) -> access_module(module, field)
        v.R(_, fields) -> {
          find_field(fields, field)
        }
        other -> Error(r.IncorrectTerm("Record", other))
      })
      Ok(#(V(value), env, ks))
    }
    RecordUpdate(module, constructor, updates) -> {
      use original <- try(case value {
        // TODO module match
        v.R(c, fields) if c == constructor -> Ok(fields)
      })
      case updates {
        [#(label, exp), ..updates] -> {
          let ks = [Update(constructor, original, label, updates), ..ks]
          Ok(#(E(exp), env, ks))
        }
        [] -> todo as "done update"
      }
    }
    Update(constructor, current, label, updates) -> {
      // This doesn't error if one is misisng
      let current =
        list.map(current, fn(field) {
          case field {
            g.Field(Some(k), _old) if k == label -> g.Field(Some(k), value)
            _ -> field
          }
        })
      case updates {
        [] -> Ok(#(V(v.R(constructor, current)), env, ks))
        [#(label, exp), ..updates] -> {
          let ks = [Update(constructor, current, label, updates), ..ks]
          Ok(#(E(exp), env, ks))
        }
      }
    }
    // Should subjects also be non empty list
    BuildSubjects([next, ..expressions], values, clauses) -> {
      let ks = [BuildSubjects(expressions, [value, ..values], clauses), ..ks]
      Ok(#(E(next), env, ks))
    }

    // TODO caring about module to match on.
    // TODO testing on guards
    BuildSubjects([], values, clauses) -> {
      let values = list.reverse([value, ..values])
      list.find_map(clauses, fn(clause) {
        list.find_map(clause.patterns, fn(patterns) {
          use bindings <- try(
            list.strict_zip(patterns, values)
            |> result.replace_error(r.IncorrectArity(
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
          Ok(#(E(clause.body), env, ks))
        })
      })
      // TODO think about having proper error from inside match
      |> result.replace_error(r.NoMatch(values))
    }
    Continue(statements) -> push_statements(statements, env, ks)
    _ -> {
      io.debug(#(value, k, ks, "---------"))
      todo as "bad apply"
    }
  }
  |> result.map_error(fn(reason) { #(reason, env, ks) })
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
      #(name, v.NamedClosure(parameters, body, dict.new()))
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
            #(name, v.Constructor(name, labels))
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
    [] -> Error(r.MissingField(label))
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
        [] -> Error(r.IncorrectArity(0, 0))
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
    v.Closure(params, body, captured), args -> {
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
                  Error(r.MissingField(label))
              }
            }),
          )
          push_statements(body, env, ks)
        }
        // TODO why is this not Nil or with values
        Error(list.LengthMismatch) ->
          Error(r.IncorrectArity(list.length(names), list.length(args)))
      }
    }
    // CAn we always use function parameters
    v.NamedClosure(params, body, captures), args -> {
      // TODO deduplicate with args above but need to add label handling
      case pair_args(params, args, []) {
        Ok(#(bindings, [])) -> {
          let env =
            list.fold(bindings, env, fn(env, new: #(_, _)) {
              dict.insert(env, new.0, new.1)
            })
          push_statements(body, env, ks)
        }
        Ok(#(_, _remaining)) ->
          Error(r.IncorrectArity(list.length(params), list.length(args)))
        // Looses size information in pairing
        Error(r.IncorrectArity(0, 0)) ->
          Error(r.IncorrectArity(list.length(params), list.length(args)))

        Error(reason) -> Error(reason)
      }
      // Error(r.IncorrectArity(list.length(names), list.length(args)))
    }
    v.Captured(f, left, right), args -> {
      // is named args supported for capture
      let assert [g.Field(None, arg)] = args
      let args =
        list.flatten([left, [arg], right])
        |> list.map(g.Field(None, _))
      call(f, args, env, ks)
    }
    // All unlabelled must go first
    v.Constructor(name, fields), args -> {
      case constuct_fields(fields, args, []) {
        Ok(fields) -> Ok(#(V(v.R(name, fields)), env, ks))
        Error(r.IncorrectArity(_, _)) ->
          Error(r.IncorrectArity(list.length(fields), list.length(args)))
        Error(reason) -> Error(reason)
      }
    }
    v.NegateInt, [a] -> negate_number(a, env, ks)
    v.NegateBool, [a] -> negate_bool(a, env, ks)
    v.BinaryOperator(op), [a, b] -> call_binop(op, a, b, env, ks)
    other, _ -> Error(r.NotAFunction(other))
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
        Error(Nil) -> Error(r.MissingField(for_error))
      }
    }
    _, _ -> Error(r.IncorrectArity(0, 0))
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

fn find_field(fields, label) {
  case fields {
    [g.Field(Some(l), value), ..] if l == label -> Ok(value)
    [_, ..fields] -> find_field(fields, label)
    [] -> Error(r.MissingField(label))
  }
}

fn negate_number(in, env, ks) {
  let assert g.Field(None, in) = in
  case in {
    v.I(v) -> Ok(#(V(v.I(-v)), env, ks))
    v.F(v) -> Ok(#(V(v.F(-1.0 *. v)), env, ks))
    _ -> Error(r.IncorrectTerm("Integer or Float", in))
  }
}

fn negate_bool(in, env, ks) {
  let assert g.Field(None, in) = in
  use in <- try(cast.as_boolean(in))
  Ok(#(V(v.bool(!in)), env, ks))
}

fn call_binop(op, a, b, env, ks) {
  // Cannot add labels when calling binop
  let assert g.Field(None, a) = a
  let assert g.Field(None, b) = b
  case op {
    g.And -> {
      use a <- try(cast.as_boolean(a))
      use b <- try(cast.as_boolean(b))
      Ok(#(V(v.bool(a && b)), env, ks))
    }
    g.Or -> {
      use a <- try(cast.as_boolean(a))
      use b <- try(cast.as_boolean(b))
      Ok(#(V(v.bool(a || b)), env, ks))
    }
    g.Eq -> {
      Ok(#(V(v.bool(a == b)), env, ks))
    }
    g.NotEq -> {
      Ok(#(V(v.bool(a != b)), env, ks))
    }
    g.LtInt -> {
      use a <- try(cast.as_integer(a))
      use b <- try(cast.as_integer(b))
      Ok(#(V(v.bool(a < b)), env, ks))
    }
    g.LtEqInt -> {
      use a <- try(cast.as_integer(a))
      use b <- try(cast.as_integer(b))
      Ok(#(V(v.bool(a <= b)), env, ks))
    }
    g.LtFloat -> {
      use a <- try(cast.as_float(a))
      use b <- try(cast.as_float(b))
      Ok(#(V(v.bool(a <. b)), env, ks))
    }
    g.LtEqFloat -> {
      use a <- try(cast.as_float(a))
      use b <- try(cast.as_float(b))
      Ok(#(V(v.bool(a <=. b)), env, ks))
    }
    g.GtEqInt -> {
      use a <- try(cast.as_integer(a))
      use b <- try(cast.as_integer(b))
      Ok(#(V(v.bool(a >= b)), env, ks))
    }
    g.GtInt -> {
      use a <- try(cast.as_integer(a))
      use b <- try(cast.as_integer(b))
      Ok(#(V(v.bool(a > b)), env, ks))
    }
    g.GtEqFloat -> {
      use a <- try(cast.as_float(a))
      use b <- try(cast.as_float(b))
      Ok(#(V(v.bool(a >=. b)), env, ks))
    }
    g.GtFloat -> {
      use a <- try(cast.as_float(a))
      use b <- try(cast.as_float(b))
      Ok(#(V(v.bool(a >. b)), env, ks))
    }
    g.Pipe -> {
      let ks = [Apply(b, None, [], [])]
      Ok(#(V(a), env, ks))
    }
    g.AddInt -> {
      use a <- try(cast.as_integer(a))
      use b <- try(cast.as_integer(b))
      Ok(#(V(v.I(a + b)), env, ks))
    }
    g.AddFloat -> {
      use a <- try(cast.as_float(a))
      use b <- try(cast.as_float(b))
      Ok(#(V(v.F(a +. b)), env, ks))
    }
    g.SubInt -> {
      use a <- try(cast.as_integer(a))
      use b <- try(cast.as_integer(b))
      Ok(#(V(v.I(a - b)), env, ks))
    }
    g.SubFloat -> {
      use a <- try(cast.as_float(a))
      use b <- try(cast.as_float(b))
      Ok(#(V(v.F(a -. b)), env, ks))
    }
    g.MultInt -> {
      use a <- try(cast.as_integer(a))
      use b <- try(cast.as_integer(b))
      Ok(#(V(v.I(a * b)), env, ks))
    }
    g.MultFloat -> {
      use a <- try(cast.as_float(a))
      use b <- try(cast.as_float(b))
      Ok(#(V(v.F(a *. b)), env, ks))
    }
    g.DivInt -> {
      use a <- try(cast.as_integer(a))
      use b <- try(cast.as_integer(b))
      Ok(#(V(v.I(a / b)), env, ks))
    }
    g.DivFloat -> {
      use a <- try(cast.as_float(a))
      use b <- try(cast.as_float(b))
      Ok(#(V(v.F(a /. b)), env, ks))
    }
    g.RemainderInt -> {
      use a <- try(cast.as_integer(a))
      use b <- try(cast.as_integer(b))
      Ok(#(V(v.I(a % b)), env, ks))
    }
    g.Concatenate -> {
      use a <- try(cast.as_string(a))
      use b <- try(cast.as_string(b))
      Ok(#(V(v.S(a <> b)), env, ks))
    }
  }
}

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
