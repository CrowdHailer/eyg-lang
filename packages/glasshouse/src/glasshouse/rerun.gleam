//// Execute recorded runs again, every effect is answered from the journal.
////
//// The content addressed program is loaded from the store, nothing is read from disk or the network.
//// A rerun that performs the same effects and returns the same result reproduces the run.

import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import glasshouse/journal.{type Entry}
import glasshouse/replay
import glasshouse/run.{type Run}
import glasshouse/secret.{type Secret}
import glasshouse/session.{type Session}
import glasshouse/store.{type Store}
import glasshouse/value
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import multiformats/cid/v1

pub type Value =
  state.Value(Nil)

pub type Scope =
  state.Scope(Nil)

pub type Problem {
  /// The run has no stored program, i.e. it did not parse.
  NoProgram
  /// A module the program needs is not in the store.
  Unavailable(reason: String)
  /// An effect differed from the recording.
  Diverged(divergence: replay.Divergence)
  /// The program raised an error.
  Raised(reason: String)
  /// The program finished with a different result.
  Different(expected: String, actual: String)
}

pub type Report {
  Report(run: Run, effects: Int, problem: Option(Problem))
}

type Ending {
  Value(Option(Value), Scope)
  Exit(status: Int)
}

/// Rerun a single run with the given scope, the scope after the run is returned for shells.
pub fn run(
  run: Run,
  store: Store,
  secrets: List(Secret),
  scope: Scope,
) -> #(Report, Scope) {
  let report = fn(effects, problem) { Report(run:, effects:, problem:) }
  case run.outcome, run.program {
    run.Rejected(..), _ -> #(report(0, None), scope)
    _, None -> #(report(0, Some(NoProgram)), scope)
    _, Some(program) ->
      case load_program(program, run, store) {
        Error(reason) -> #(report(0, Some(Unavailable(reason))), scope)
        Ok(source) -> {
          let cursor = replay.start(run.journal, store, secrets)
          let #(ending, cursor) =
            loop(block.execute(source, scope), store, cursor, dict.new())
          let effects = replay.position(cursor)
          case ending {
            Error(problem) -> #(report(effects, Some(problem)), scope)
            Ok(ending) -> {
              let finished = case ending {
                Exit(_) -> Ok(Nil)
                Value(..) -> replay.finish(cursor)
              }
              case finished {
                Error(divergence) -> #(
                  report(effects, Some(Diverged(divergence))),
                  scope,
                )
                Ok(Nil) -> {
                  let scope = case ending {
                    Value(_, scope) -> scope
                    Exit(_) -> scope
                  }
                  #(
                    report(effects, compare(run, ending, store, secrets)),
                    scope,
                  )
                }
              }
            }
          }
        }
      }
  }
}

fn load_program(program, run: Run, store) {
  use node <- result.map(store.get_node(store, program))
  case run.kind {
    run.Script(arguments:) -> {
      let arguments =
        list.fold_right(arguments, #(ir.Tail, Nil), fn(tail, argument) {
          #(
            ir.Apply(
              #(ir.Apply(#(ir.Cons, Nil), #(ir.String(argument), Nil)), Nil),
              tail,
            ),
            Nil,
          )
        })
      #(
        ir.Apply(#(ir.Apply(#(ir.Select("script"), Nil), node), Nil), arguments),
        Nil,
      )
    }
    _ -> node
  }
}

fn loop(return, store, cursor, modules: Dict(String, Value)) {
  case return {
    Ok(#(value, scope)) -> #(Ok(Value(value, scope)), cursor)
    Error(#(break.UnhandledEffect(label, lift), _, env, k)) ->
      case replay.next(cursor, label, lift, Nil) {
        Ok(#(reply, _entry, cursor)) ->
          case label, lift {
            "Exit", v.Integer(status) -> #(Ok(Exit(status)), cursor)
            _, _ -> loop(block.resume(reply, env, k), store, cursor, modules)
          }
        Error(divergence) -> #(Error(Diverged(divergence)), cursor)
      }
    Error(#(break.UndefinedReference(reference), _, env, k)) ->
      case module(reference, store, modules) {
        Ok(#(value, modules)) ->
          loop(block.resume(value, env, k), store, cursor, modules)
        Error(reason) -> #(Error(Unavailable(reason)), cursor)
      }
    Error(#(reason, _, _, _)) -> #(
      Error(Raised(simple_debug.describe(reason))),
      cursor,
    )
  }
}

fn module(reference, store, modules) {
  let cid = case reference {
    ir.Content(cid:) -> Ok(cid)
    ir.Pinned(release:) -> Ok(release.module)
    _ ->
      Error(
        "the program has an unpinned reference "
        <> ir.reference_to_string(reference),
      )
  }
  use cid <- result.try(cid)
  let id = v1.to_string(cid)
  case dict.get(modules, id) {
    Ok(value) -> Ok(#(value, modules))
    Error(Nil) -> {
      use node <- result.try(store.get_node(store, id))
      use #(value, modules) <- result.map(pure(
        expression.execute(node, []),
        store,
        modules,
      ))
      #(value, dict.insert(modules, id, value))
    }
  }
}

fn pure(return, store, modules) {
  case return {
    Ok(value) -> Ok(#(value, modules))
    Error(#(break.UndefinedReference(reference), _, env, k)) -> {
      use #(value, modules) <- result.try(module(reference, store, modules))
      pure(expression.resume(value, env, k), store, modules)
    }
    Error(#(reason, _, _, _)) -> Error(simple_debug.describe(reason))
  }
}

fn compare(run: Run, ending, store, secrets) -> Option(Problem) {
  case run.outcome, ending {
    run.Returned(expected), Value(Some(actual), _) -> {
      let actual = case run.kind {
        // Configurations hold credentials, only their context is recorded.
        run.Config -> cast.field("context", Ok, actual) |> result.unwrap(actual)
        _ -> actual
      }
      let actual = secret.redact(actual, secrets)
      case value.matches(actual, expected, store) {
        True -> None
        False ->
          Some(Different(
            value.render(expected, store),
            simple_debug.inspect(actual),
          ))
      }
    }
    run.Finished, Value(None, _) -> None
    run.Exited(expected), Exit(actual) if expected == actual -> None
    run.Failed(_), _ -> Some(Different("an error", describe_ending(ending)))
    expected, _ ->
      Some(Different(describe_outcome(expected, store), describe_ending(ending)))
  }
}

fn describe_outcome(outcome, store) {
  case outcome {
    run.Returned(encoded) -> value.render(encoded, store)
    run.Finished -> "no value"
    run.Exited(status) -> "exit " <> int.to_string(status)
    run.Failed(reason) -> reason
    run.Rejected(reason) -> reason
  }
}

fn describe_ending(ending) {
  case ending {
    Value(Some(value), _) -> simple_debug.inspect(value)
    Value(None, _) -> "no value"
    Exit(status) -> "exit " <> int.to_string(status)
  }
}

/// Substitutes for every secret a run's journal mounted.
pub fn dummy_secrets(journal: List(Entry), store: Store) -> List(Secret) {
  list.filter_map(journal, fn(entry) {
    case entry.label, value.decode(entry.lift, store, Nil) {
      "MountSecret", Ok(v.String(name)) -> Ok(secret.dummy(name))
      "Env", Ok(v.String(name)) ->
        case secret.is_credential_variable(name) {
          True -> Ok(secret.dummy(secret.variable_name(name)))
          False -> Error(Nil)
        }
      _, _ -> Error(Nil)
    }
  })
  |> list.unique
}

/// Rerun every run in a session, in order.
/// Tool calls run with the context the configuration recorded, shell inputs share a scope.
pub fn session(session: Session, store: Store) -> List(Report) {
  session_with_secrets(session, store, [])
}

/// Rerun a session with the real value of some secrets, i.e. local copies that match the hashes in the locks.
/// Every other secret is replaced by a dummy.
pub fn session_with_secrets(
  session: Session,
  store: Store,
  known: List(Secret),
) -> List(Report) {
  let runs = session.runs(session)
  let secrets =
    list.flat_map(runs, fn(run) { dummy_secrets(run.journal, store) })
    |> list.unique
    |> list.map(fn(dummy) {
      list.find(known, fn(secret) { secret.name == dummy.name })
      |> result.unwrap(dummy)
    })
  let context =
    list.find_map(runs, fn(run) {
      case run.kind, run.outcome {
        run.Config, run.Returned(encoded) ->
          value.decode(encoded, store, Nil) |> result.replace_error(Nil)
        _, _ -> Error(Nil)
      }
    })
  let #(_, reports) =
    list.fold(runs, #([], []), fn(acc, recorded) {
      let #(cells, reports) = acc
      let scope = case recorded.kind, context {
        run.Tool(..), Ok(context) -> [
          #("context", secret.restore(context, secrets)),
        ]
        run.Cell, _ -> cells
        _, _ -> []
      }
      let #(report, scope) = run(recorded, store, secrets, scope)
      let cells = case recorded.kind, report.problem {
        run.Cell, None -> scope
        _, _ -> cells
      }
      #(cells, [report, ..reports])
    })
  list.reverse(reports)
}

pub fn describe(problem: Problem, store: Store) -> String {
  case problem {
    NoProgram -> "the run has no program"
    Unavailable(reason:) -> "a module is missing: " <> reason
    Diverged(divergence:) -> replay.describe(divergence, store)
    Raised(reason:) -> "the program raised an error: " <> reason
    Different(expected:, actual:) ->
      "the result differs, recorded "
      <> expected
      <> " but the rerun returned "
      <> actual
  }
}
