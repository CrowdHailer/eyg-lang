import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/proof
import eyg/interpreter/table
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string

pub type Context(m) =
  #(List(#(Kontinue(m), m)), Env(m))

pub type Value(m) =
  v.Value(m, Context(m))

pub type Reason(m) =
  break.Reason(m, Context(m))

pub type Control(m) {
  E(#(ir.Expression(m), m))
  V(Value(m))
  /// Keep invocation explicit so alternate runners can observe every call,
  /// including callbacks invoked by builtins and effect handlers.
  Call(Value(m), Value(m), m)
}

pub type Debug(m) =
  #(Reason(m), m, Env(m), Stack(m))

pub type Next(m) {
  Loop(Control(m), Env(m), Stack(m))
  Break(Result(Value(m), Debug(m)))
}

pub type Scope(m) =
  List(#(String, Value(m)))

// Env and Stack(m) also rely on each other
// Env as a type (not alias breaks recursive type definition up to continue)
// builtins are passed in the env because builtin definition relies on interpreter state and we get a circular dependency
// 
// The env is returned from loop functions,
// it's a simpler API for callers to pass the same Env type back rather than unwrap to just the scope
// 
// The only fix to remove builtins I can see is to write all builtins in the state module
pub type Env(m) {
  Env(scope: Scope(m), builtins: Dict(String, Builtin(m)))
}

pub type Return(m) =
  Result(#(Control(m), Env(m), Stack(m)), Reason(m))

pub type Builtin(m) {
  Arity1(fn(Value(m), m, Env(m), Stack(m)) -> Return(m))
  Arity2(fn(Value(m), Value(m), m, Env(m), Stack(m)) -> Return(m))
  Arity3(fn(Value(m), Value(m), Value(m), m, Env(m), Stack(m)) -> Return(m))
  Arity4(
    fn(Value(m), Value(m), Value(m), Value(m), m, Env(m), Stack(m)) -> Return(m),
  )
}

pub type Stack(m) {
  Stack(Kontinue(m), m, Stack(m))
  Empty
}

/// Fixed-point evaluation of one `resolve`. Every rule in a round sees the same
/// `snapshot`. A rule is only run again when a relation it matched last time grew,
/// pure rules read the snapshot only through `Match`, so its output would not change.
pub type Resolution(m) {
  Resolution(
    label: String,
    snapshot: Dict(String, Dict(Value(m), Int)),
    facts: Dict(String, Dict(Value(m), Int)),
    rules: List(#(Int, Value(m))),
    pending: List(#(Int, Value(m))),
    reads: Dict(Int, Set(String)),
    current: Int,
    reading: Set(String),
    grown: Set(String),
    // Relations only grow while resolving, an index is current while the
    // relation it was built from has the same size.
    indexes: Dict(
      #(String, List(String)),
      #(Int, Dict(Value(m), List(Value(m)))),
    ),
    env: Env(m),
    proofs: Option(proof.Store(m, Context(m))),
  )
}

pub type Kontinue(m) {
  /// Opt-in host boundary; explain.advance extracts this trace on completion.
  Explain(List(proof.Query(m, Context(m))))
  /// Evidence scoped to one matched branch or successful query predicate.
  Premise(proof.Tree(m, Context(m)))
  QueryNext(Resolution(m))
  /// Union the tables returned by `then` for each remaining matched row.
  MatchNext(
    rows: List(#(Value(m), Option(proof.Tree(m, Context(m))))),
    then: Value(m),
    acc: Dict(String, Dict(Value(m), Int)),
    env: Env(m),
  )
  Arg(ir.Node(m), Env(m))
  Apply(Value(m), Env(m))
  Assign(String, ir.Node(m), Env(m))
  CallWith(Value(m), Env(m))
  /// None is deep; Some(on_return) is shallow with an explicit return clause.
  Delimit(String, Value(m), Env(m), Option(Value(m)))
  Mask(String)
  Pure
  /// Restore the caller's environment when a closure or continuation returns,
  /// including after an effect resumes. The argument is used in stack traces.
  Trace(Value(m), Env(m))
  /// Used only by the profiling runner. Unlike Trace, this is not tail-elided.
  ProfileReturn(Int, Env(m))
}

pub fn step(c, env, k) {
  case c, k {
    Call(f, arg, meta), k -> {
      invoke(f, arg, meta, env, k)
      |> result.map_error(fn(reason) { #(reason, meta, env, k) })
      |> try
    }
    E(exp), k -> try(eval(exp, env, k))
    V(value), Empty -> Break(Ok(value))
    V(value), Stack(k, meta, rest) -> try(apply(value, env, k, meta, rest))
  }
}

pub fn try(return) {
  case return {
    Ok(#(c, e, k)) -> Loop(c, e, k)
    Error(info) -> Break(Error(info))
  }
}

pub fn eval(exp, env: Env(m), k) {
  let #(exp, meta) = exp
  let value = fn(value) { Ok(#(V(value), env, k)) }
  case exp {
    ir.Lambda(param, body) ->
      Ok(#(V(v.Closure(param, body, env.scope)), env, k))

    ir.Apply(f, arg) -> Ok(#(E(f), env, Stack(Arg(arg, env), meta, k)))

    ir.Variable(x) ->
      case list.key_find(env.scope, x) {
        Ok(term) -> Ok(#(V(term), env, k))
        Error(Nil) -> Error(break.UndefinedVariable(x))
      }

    ir.Let(var, value, then) ->
      Ok(#(E(value), env, Stack(Assign(var, then, env), meta, k)))

    ir.Binary(data) -> value(v.Binary(data))
    ir.Integer(data) -> value(v.Integer(data))
    ir.String(data) -> value(v.String(data))
    ir.Query(ir.EmptyTable) -> value(v.Table(dict.new(), []))
    ir.Query(operation) -> value(v.Partial(v.Query(operation), []))
    ir.Tail -> value(v.LinkedList([]))
    ir.Cons -> value(v.Partial(v.Cons, []))
    ir.Vacant -> Error(break.Vacant)
    ir.Select(label) -> value(v.Partial(v.Select(label), []))
    ir.Tag(label) -> value(v.Partial(v.Tag(label), []))
    ir.Perform(label) -> value(v.Partial(v.Perform(label), []))
    ir.Empty -> value(v.unit())
    ir.Extend(label) -> value(v.Partial(v.Extend(label), []))
    ir.Overwrite(label) -> value(v.Partial(v.Overwrite(label), []))
    ir.Case(label) -> value(v.Partial(v.Match(label), []))
    ir.NoCases -> value(v.Partial(v.NoCases, []))
    ir.Handle(label) -> value(v.Partial(v.Handle(label), []))
    ir.Shallow(label) -> value(v.Partial(v.Shallow(label), []))
    ir.Mask(label) -> value(v.Partial(v.Mask(label), []))
    ir.Builtin(identifier) ->
      case dict.get(env.builtins, identifier) {
        Ok(_) -> value(v.Partial(v.Builtin(identifier), []))
        _ -> Error(break.UndefinedBuiltin(identifier))
      }
    ir.Reference(reference) -> Error(break.UndefinedReference(reference))
  }
  |> result.map_error(fn(reason) { #(reason, meta, env, k) })
}

pub fn apply(value, env, k, meta, rest) {
  case k {
    Explain(_) -> Ok(#(V(value), env, rest))
    Premise(tree) -> {
      // A host-written rule may return a preconstructed table rather than call
      // Fact at its head. Preserve the successful branch's evidence as well.
      let rest = record_returned(value, tree, meta, rest)
      Ok(#(V(value), env, rest))
    }
    Assign(label, then, env) -> {
      let env = Env(..env, scope: [#(label, value), ..env.scope])
      Ok(#(E(then), env, rest))
    }
    Arg(arg, env) -> Ok(#(E(arg), env, Stack(Apply(value, env), meta, rest)))
    Apply(f, env) -> call(f, value, meta, env, rest)
    CallWith(arg, env) -> call(value, arg, meta, env, rest)
    Delimit(_, _, env, None) -> Ok(#(V(value), env, rest))
    Delimit(_, _, env, Some(on_return)) ->
      call(on_return, value, meta, env, rest)
    Trace(_, env) -> Ok(#(V(value), env, rest))
    ProfileReturn(_, env) -> Ok(#(V(value), env, rest))
    Mask(_) | Pure -> Ok(#(V(value), env, rest))
    QueryNext(resolution) -> {
      use #(derived, nested) <- result.try(cast.as_table(value))
      case nested {
        [] -> {
          let #(facts, grown) = table.merge(resolution.facts, derived)
          let resolution =
            Resolution(
              ..resolution,
              facts:,
              reads: dict.insert(
                resolution.reads,
                resolution.current,
                resolution.reading,
              ),
              grown: set.union(resolution.grown, grown),
              proofs: option.map(resolution.proofs, fn(store) {
                proof.commit(store, derived, resolution.current, meta)
              }),
            )
          query_next(resolution, meta, rest)
        }
        _ -> Error(break.IncorrectTerm("facts returned by a rule", value))
      }
    }
    MatchNext(rows, then, acc, env) -> {
      use #(derived, nested) <- result.try(cast.as_table(value))
      case nested {
        [] ->
          match_next(rows, then, table.merge(acc, derived).0, meta, env, rest)
        _ -> Error(break.IncorrectTerm("facts returned by a rule", value))
      }
    }
  }
  |> result.map_error(fn(reason) { #(reason, meta, env, rest) })
}

pub fn call(f, arg, meta, env: Env(m), k: Stack(m)) {
  Ok(#(Call(f, arg, meta), env, k))
}

fn invoke(f, arg, meta, env: Env(m), k: Stack(m)) {
  case f {
    v.Closure(param, body, captured) -> {
      let k = trace(arg, meta, env, k)
      let env = Env(..env, scope: [#(param, arg), ..captured])
      Ok(#(E(body), env, k))
    }
    // builtin needs to return result for the case statement
    // Resume/Deep need access to k nothing needs access to env but extension might change that
    v.Partial(switch, applied) ->
      case switch, applied {
        v.Query(ir.Fact(label)), [] -> {
          let k = record_derivation(label, arg, meta, k)
          Ok(#(V(v.Table(table.singleton(label, arg), [])), env, k))
        }
        v.Query(ir.Rule), [] -> Ok(#(V(v.Table(dict.new(), [arg])), env, k))
        v.Query(ir.Merge), [left] -> {
          use #(left_facts, left_rules) <- result.try(cast.as_table(left))
          use #(right_facts, right_rules) <- result.try(cast.as_table(arg))
          Ok(#(
            V(v.Table(
              table.merge(left_facts, right_facts).0,
              list.append(left_rules, right_rules),
            )),
            env,
            k,
          ))
        }
        v.Query(ir.Resolve(label)), [] -> {
          use #(facts, rules) <- result.try(cast.as_table(arg))
          let proofs = case explaining(k) {
            True -> Some(proof.seed(facts))
            False -> None
          }
          use <- bool.lazy_guard(rules == [], fn() {
            let #(_, k) = matching(facts, label, [], v.unit(), k)
            let k = record_query(proofs, label, facts, k)
            Ok(#(V(v.LinkedList(table.rows(facts, label))), env, k))
          })
          let rules = list.index_map(rules, fn(rule, i) { #(i, rule) })
          Resolution(
            label:,
            snapshot: facts,
            facts:,
            rules:,
            pending: rules,
            reads: dict.new(),
            current: 0,
            reading: set.new(),
            grown: set.new(),
            indexes: dict.new(),
            env:,
            proofs:,
          )
          |> query_next(meta, k)
        }
        v.Query(ir.Match(label, keys)), [db, key] -> {
          use #(facts, _rules) <- result.try(cast.as_table(db))
          let #(rows, k) = matching(facts, label, keys, key, k)
          let rows = matched_proofs(facts, label, rows, k)
          match_next(rows, arg, dict.new(), meta, env, k)
        }
        v.Cons, [item] -> {
          use elements <- result.try(cast.as_list(arg))
          Ok(#(V(v.LinkedList([item, ..elements])), env, k))
        }
        v.Extend(label), [value] -> {
          use fields <- result.try(cast.as_record(arg))
          let fields = dict.insert(fields, label, value)
          Ok(#(V(v.Record(fields)), env, k))
        }
        v.Overwrite(label), [value] -> {
          use fields <- result.try(cast.as_record(arg))
          use _ <- result.try(
            dict.get(fields, label)
            |> result.replace_error(break.MissingField(label)),
          )
          let fields = dict.insert(fields, label, value)
          Ok(#(V(v.Record(fields)), env, k))
        }
        v.Select(label), [] -> {
          use fields <- result.try(cast.as_record(arg))
          use value <- result.try(
            dict.get(fields, label)
            |> result.replace_error(break.MissingField(label)),
          )
          Ok(#(V(value), env, k))
        }
        v.Tag(label), [] -> Ok(#(V(v.Tagged(label, arg)), env, k))
        v.Match(label), [branch, otherwise] -> {
          use #(l, inner) <- result.try(cast.as_tagged(arg))
          case l == label {
            True -> {
              let k = record_predicate(label, branch, meta, env, k)
              call(branch, inner, meta, env, k)
            }
            False -> call(otherwise, arg, meta, env, k)
          }
        }
        v.NoCases, [] -> Error(break.NoMatch(arg))
        v.Perform(label), [] -> perform(label, arg, env, k)
        v.Handle(label), [handler] -> deep(label, handler, arg, meta, env, k)
        v.Shallow(label), [handler, on_return] ->
          shallow(label, handler, on_return, arg, meta, env, k)
        v.Mask(label), [] ->
          call(arg, v.unit(), meta, env, Stack(Mask(label), meta, k))
        v.Pure, [function] ->
          call(function, arg, meta, env, Stack(Pure, meta, k))
        v.Resume(#(popped, captured)), [] -> {
          let k = trace(arg, meta, env, k)
          Ok(#(V(arg), captured, move(popped, k)))
        }
        v.Builtin(key), applied ->
          call_builtin(key, list.append(applied, [arg]), meta, env, k)

        switch, _ -> {
          let applied = list.append(applied, [arg])
          Ok(#(V(v.Partial(switch, applied)), env, k))
        }
      }

    term -> Error(break.NotAFunction(term))
  }
}

// can return a expression body
fn call_builtin(key, applied, meta, env: Env(m), kont) {
  case dict.get(env.builtins, key) {
    Ok(func) ->
      case func, applied {
        // impl uses path to build stack when calling functions passed in
        // might not need it as fn's keep track of path
        Arity1(impl), [x] -> impl(x, meta, env, kont)
        Arity2(impl), [x, y] -> impl(x, y, meta, env, kont)
        Arity3(impl), [x, y, z] -> impl(x, y, z, meta, env, kont)
        Arity4(impl), [x, y, z, a] -> impl(x, y, z, a, meta, env, kont)
        _, _args -> Ok(#(V(v.Partial(v.Builtin(key), applied)), env, kont))
      }
    Error(Nil) -> Error(break.UndefinedBuiltin(key))
  }
}

// In interpreter because circular dependencies interpreter -> spec -> stdlib/linked list

// A Trace at the top means the caller has no work left besides returning.
// Keep the latest call site, but restore the original caller's environment.
// This stops the stack growing in effect handling
fn trace(arg, meta, env, k) {
  case k {
    Stack(Trace(_, caller), _, rest) -> Stack(Trace(arg, caller), meta, rest)
    _ -> Stack(Trace(arg, env), meta, k)
  }
}

fn move(delimited, acc) {
  case delimited {
    [] -> acc
    [#(Trace(arg, env), meta), ..rest] -> move(rest, trace(arg, meta, env, acc))
    [#(step, meta), ..rest] -> move(rest, Stack(step, meta, acc))
  }
}

fn do_perform(label, arg, i_env, k, acc, skip) {
  case k {
    Stack(Pure, _, _) -> Error(break.ImpureEffect(label, arg))
    Stack(Mask(l), meta, rest) if l == label ->
      do_perform(label, arg, i_env, rest, [#(Mask(l), meta), ..acc], skip + 1)
    Stack(Delimit(l, h, e, on_return), meta, rest) if l == label && skip > 0 ->
      do_perform(
        label,
        arg,
        i_env,
        rest,
        [#(Delimit(l, h, e, on_return), meta), ..acc],
        skip - 1,
      )
    Stack(Delimit(l, h, e, on_return), meta, rest) if l == label -> {
      let acc = case on_return {
        Some(_) -> acc
        None -> [#(Delimit(label, h, e, None), meta), ..acc]
      }
      let resume = v.Partial(v.Resume(#(acc, i_env)), [])
      let k =
        Stack(CallWith(arg, e), meta, Stack(CallWith(resume, e), meta, rest))
      Ok(#(V(h), e, k))
    }
    Stack(QueryNext(..), _, _) -> Error(break.ImpureQuery(label))
    Stack(kontinue, meta, rest) ->
      do_perform(label, arg, i_env, rest, [#(kontinue, meta), ..acc], skip)
    Empty if skip > 0 -> Error(break.MaskedEffect(label, arg))
    Empty -> Error(break.UnhandledEffect(label, arg))
  }
}

pub fn perform(label, arg, i_env, k: Stack(m)) {
  do_perform(label, arg, i_env, k, [], 0)
}

// rename handle and move the handle for runner with handles out
pub fn deep(label, handle, exec, meta, env, k) {
  let k = Stack(Delimit(label, handle, env, None), meta, k)
  call(exec, v.unit(), meta, env, k)
}

pub fn shallow(label, handle, on_return, exec, meta, env, k) {
  let k = Stack(Delimit(label, handle, env, Some(on_return)), meta, k)
  call(exec, v.unit(), meta, env, k)
}

// somewhere this needs outer k
// fn shallow(label, handle, exec, meta, env, k) {
//   let k = Stack(Delimit(label, handle, env, True), meta, k)
//   call(exec, v.unit(), meta, env, k)
// }

fn query_next(resolution: Resolution(m), meta: m, k: Stack(m)) -> Return(m) {
  case resolution.pending {
    [#(index, rule), ..pending] -> {
      let resolution =
        Resolution(
          ..resolution,
          pending:,
          current: index,
          reading: set.new(),
          proofs: option.map(resolution.proofs, proof.begin_rule),
        )
      let db = v.Table(resolution.snapshot, [])
      let k = Stack(QueryNext(resolution), meta, k)
      call(rule, db, meta, resolution.env, k)
    }
    [] ->
      case set.is_empty(resolution.grown) {
        True -> {
          let rows = table.rows(resolution.facts, resolution.label)
          let k =
            record_query(
              resolution.proofs,
              resolution.label,
              resolution.facts,
              k,
            )
          Ok(#(V(v.LinkedList(rows)), resolution.env, k))
        }
        False -> {
          let Resolution(rules:, reads:, grown:, ..) = resolution
          let pending =
            list.filter(rules, fn(rule) {
              case dict.get(reads, rule.0) {
                Ok(read) -> !set.is_empty(set.intersection(read, grown))
                Error(Nil) -> True
              }
            })
          Resolution(
            ..resolution,
            snapshot: resolution.facts,
            pending:,
            grown: set.new(),
          )
          |> query_next(meta, k)
        }
      }
  }
}

fn match_next(
  rows: List(#(Value(m), Option(proof.Tree(m, Context(m))))),
  then: Value(m),
  acc: Dict(String, Dict(Value(m), Int)),
  meta: m,
  env: Env(m),
  k: Stack(m),
) -> Return(m) {
  case rows {
    [#(row, evidence), ..rows] -> {
      let k = Stack(MatchNext(rows, then, acc, env), meta, k)
      let k = case evidence {
        Some(tree) -> Stack(Premise(tree), meta, k)
        None -> k
      }
      call(then, row, meta, env, k)
    }
    [] -> Ok(#(V(v.Table(acc, [])), env, k))
  }
}

// Rows of the snapshot are found through an index cached on the enclosing
// resolution, which also records the relation as read by the running rule.
fn matching(
  facts: Dict(String, Dict(Value(m), Int)),
  label: String,
  keys: List(String),
  key: Value(m),
  k: Stack(m),
) -> #(List(Value(m)), Stack(m)) {
  case find_resolution(k, []) {
    Ok(#(resolution, meta, above, rest)) if facts == resolution.snapshot -> {
      let size = table.relation_size(facts, label)
      let #(index, indexes) = case
        dict.get(resolution.indexes, #(label, keys))
      {
        Ok(#(indexed, index)) if indexed == size -> #(index, resolution.indexes)
        _ -> {
          let index = table.index(facts, label, keys)
          let indexes =
            dict.insert(resolution.indexes, #(label, keys), #(size, index))
          #(index, indexes)
        }
      }
      let reading = set.insert(resolution.reading, label)
      let resolution = Resolution(..resolution, reading:, indexes:)
      let k =
        list.fold(above, Stack(QueryNext(resolution), meta, rest), fn(k, frame) {
          Stack(frame.0, frame.1, k)
        })
      #(dict.get(index, key) |> result.unwrap([]), k)
    }
    _ -> {
      let rows =
        table.rows(facts, label)
        |> list.filter(fn(row) { table.key(row, keys) == Ok(key) })
      #(rows, k)
    }
  }
}

fn find_resolution(k, above) {
  case k {
    Stack(QueryNext(resolution), meta, rest) ->
      Ok(#(resolution, meta, above, rest))
    Stack(frame, meta, rest) -> find_resolution(rest, [#(frame, meta), ..above])
    Empty -> Error(Nil)
  }
}

fn explaining(k) {
  case k {
    Empty -> False
    Stack(Explain(_), _, _) -> True
    Stack(_, _, rest) -> explaining(rest)
  }
}

fn matched_proofs(facts, label, rows, k) {
  let #(store, same_snapshot) = case find_resolution(k, []) {
    Ok(#(resolution, _, _, _)) -> #(
      resolution.proofs,
      resolution.snapshot == facts,
    )
    Error(Nil) -> #(None, False)
  }
  list.map(rows, fn(row) {
    let tree =
      option.map(store, fn(store) {
        case same_snapshot {
          True -> proof.lookup(store, label, row)
          False -> proof.Fact(label, row)
        }
      })
    #(row, tree)
  })
}

fn record_derivation(label, row, at, k) {
  case find_resolution(k, []) {
    Ok(#(resolution, meta, above, rest)) if resolution.proofs != None -> {
      let premises =
        list.filter_map(above, fn(frame) {
          case frame.0 {
            Premise(tree) -> Ok(tree)
            _ -> Error(Nil)
          }
        })
      let proofs =
        option.map(resolution.proofs, fn(store) {
          proof.record(store, label, row, resolution.current, at, premises)
        })
      let resolution = Resolution(..resolution, proofs:)
      list.fold(above, Stack(QueryNext(resolution), meta, rest), fn(k, frame) {
        Stack(frame.0, frame.1, k)
      })
    }
    _ -> k
  }
}

fn record_returned(value, tree, meta, rest) {
  case value, find_resolution(rest, []) {
    v.Table(facts, _), Ok(#(Resolution(proofs: Some(_), ..), _, _, _)) -> {
      let k = Stack(Premise(tree), meta, rest)
      let k =
        dict.fold(facts, k, fn(k, label, rows) {
          dict.fold(rows, k, fn(k, row, _) {
            record_derivation(label, row, meta, k)
          })
        })
      case k {
        Stack(_, _, rest) -> rest
        Empty -> rest
      }
    }
    _, _ -> rest
  }
}

fn record_predicate(label, branch, at, env: Env(m), k) {
  case label, branch {
    "True", v.Closure("$unit", _, _) -> {
      case find_resolution(k, []) {
        Ok(#(Resolution(proofs: Some(_), ..), _, _, _)) -> {
          let #(_, bindings) =
            list.fold(env.scope, #(set.new(), []), fn(acc, pair) {
              let #(seen, bindings) = acc
              let scalar = case pair.1 {
                v.String(_) | v.Integer(_) -> True
                v.Tagged("True", _) | v.Tagged("False", _) -> True
                _ -> False
              }
              case
                scalar
                && !string.starts_with(pair.0, "$")
                && !set.contains(seen, pair.0)
              {
                True -> #(
                  set.insert(seen, pair.0),
                  list.append(bindings, [pair]),
                )
                False -> #(set.insert(seen, pair.0), bindings)
              }
            })
          Stack(Premise(proof.Predicate(at, bindings)), at, k)
        }
        _ -> k
      }
    }
    _, _ -> k
  }
}

fn record_query(proofs, label, facts, k) {
  case proofs {
    None -> k
    Some(store) -> append_query(proof.query(store, label, facts), k)
  }
}

fn append_query(query, k) {
  case k {
    Empty -> Empty
    Stack(Explain(queries), meta, rest) ->
      Stack(Explain([query, ..queries]), meta, rest)
    Stack(frame, meta, rest) -> Stack(frame, meta, append_query(query, rest))
  }
}
