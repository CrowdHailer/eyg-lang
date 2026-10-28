import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug as type_debug
import eyg/analysis/type_/isomorphic as t
import eyg/cli/internal/config
import eyg/cli/internal/traces
import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/simple_debug
import eyg/ir/tree
import eyg/parser
import eyg/parser/parser.{UnexpectEnd} as _
import glasshouse/archive
import glasshouse/recorder.{type Recorder}
import glasshouse/run
import glasshouse/session as trace
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import loam/execute
import loam/ir
import loam/pin
import loam/record
import loam/source
import loam/system

pub fn execute(input, config: config.Config) {
  use initial <- system.then(initialize(input, config))
  use #(scope, state) <- system.try(initial)
  use Nil <- system.then(system.stdout("type /help for shell commands"))
  loop("", scope, [], state)
}

/// Prepare a shell without taking ownership of terminal input or output.
/// Frontends can then call `handle` while retaining the returned scope and cache.
pub fn initialize(input, config: config.Config) {
  let state = config.state(config)
  read_input(input, state)
}

pub fn read_input(input, state) {
  case input {
    Some(input) -> {
      use cwd <- system.then(system.cwd())
      use cwd <- system.try(cwd)
      use input <- system.try(source.normalize_input(cwd, input))
      use code <- system.then(source.read_input(input))
      use code <- system.try(code)
      use source <- system.try(source.parse_input(code, input))
      let source = ir.apply(ir.apply(ir.select("shell"), source), ir.unit())
      use #(result, state) <- system.map(execute.block(source, [], state))
      case result {
        Ok(#(_, scope)) -> Ok(#(scope, state))
        Error(#(break.UnhandledEffect("Break", _), _, env, _)) ->
          Ok(#(env.scope, state))
        Error(#(reason, location, _, k)) -> {
          Error(execute.render_error(reason, location, k, cwd))
        }
      }
    }
    None -> system.Done(Ok(#([], state)))
  }
}

// `defs` is the assignments entered so far, kept so `/type` can type
// check an expression against the variables in scope. The runtime
// `scope` holds values, not types, so type checking re-runs inference
// over the accumulated definitions.
fn loop(buffer, scope, defs, state: execute.State) -> system.Effect(_) {
  use input <- system.then(system.prompt("> "))
  case input {
    Ok("") -> system.Done(Ok(0))
    Ok(code) -> {
      let code = case buffer {
        "" -> code
        _ -> buffer <> "\n" <> code
      }
      use #(output, #(buffer, scope, defs, state)) <- system.then(handle(
        code,
        scope,
        defs,
        state,
      ))

      use _ <- system.then(
        system.traverse(output, fn(line) {
          case line {
            Ok(line) -> system.stdout(line)
            Error(line) -> system.write_stderr(line <> "\n")
          }
        }),
      )
      loop(buffer, scope, defs, state)
    }
    Error(Nil) -> system.Done(Error("failed input."))
  }
}

/// Everything recorded in a shell session.
type Recording {
  Recording(
    id: String,
    started: Int,
    cwd: String,
    recorder: Recorder,
    /// Newest first.
    events: List(trace.Event),
  )
}

/// A shell where every input is pinned and its effects recorded.
/// The session is saved after each input so it can be replayed, even when the shell is stopped.
pub fn record(config: config.Config) -> system.Effect(Result(Int, String)) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use started <- system.then(system.now())
  use id <- system.then(traces.new_id(started))
  let state = config.state(config)
  let recording =
    Recording(
      id:,
      started:,
      cwd:,
      recorder: recorder.new(traces.sha256),
      events: [],
    )
  use Nil <- system.then(system.stdout(
    "recording to " <> id <> ", type /help for shell commands",
  ))
  record_loop("", [], [], state, recording)
}

fn record_loop(buffer, scope, defs, state, recording: Recording) {
  use input <- system.then(system.prompt("> "))
  case input {
    Ok("") -> {
      use saved <- system.then(save(recording))
      use path <- system.try(saved)
      use Nil <- system.then(system.stdout("trace saved to " <> path))
      system.Done(Ok(0))
    }
    Ok(code) -> {
      let code = case buffer {
        "" -> code
        _ -> buffer <> "\n" <> code
      }
      use #(output, #(buffer, scope, defs, state), recording) <- system.then(
        case code {
          "/" <> command -> {
            use #(output, next) <- system.map(handle_meta(
              command,
              scope,
              defs,
              state,
            ))
            #(output, next, recording)
          }
          _ -> record_cell(code, scope, defs, state, recording)
        },
      )
      use _ <- system.then(
        system.traverse(output, fn(line) {
          case line {
            Ok(line) -> system.stdout(line)
            Error(line) -> system.write_stderr(line <> "\n")
          }
        }),
      )
      record_loop(buffer, scope, defs, state, recording)
    }
    Error(Nil) -> system.Done(Error("failed input."))
  }
}

fn record_cell(code, scope, defs, state, recording: Recording) {
  case parser.block_from_string(code) {
    Error(UnexpectEnd) ->
      system.Done(#([], #(code, scope, defs, state), recording))
    Error(reason) ->
      system.Done(#(
        [Error(parser.format_error(reason, code))],
        #("", scope, defs, state),
        recording,
      ))
    Ok(#(#(assignments, tail), _)) -> {
      let tail = option.unwrap(tail, #(tree.Vacant, #(0, 0)))
      let located =
        list.fold_right(assignments, tail, fn(acc, assignment) {
          let #(label, value, at) = assignment
          #(tree.Let(label, value, acc), at)
        })
        |> tree.map_annotation(fn(span) {
          source.Location(source.Repl, source.Text(code, span))
        })
      let Recording(cwd:, ..) = recording
      let recorder = recorder.restart(recording.recorder)
      use started <- system.then(system.now())
      use #(pinned, state, recorder) <- system.then(pin.pin(
        located,
        cwd,
        state,
        recorder,
        pin.allow,
      ))
      case pinned {
        Error(reason) ->
          system.Done(#([Error(reason)], #("", scope, defs, state), recording))
        Ok(pinned) -> {
          use #(outcome, recorder, Nil) <- system.then(record.run_block(
            located,
            scope,
            pinned,
            cwd,
            recorder,
            record.computer,
            Nil,
          ))
          use ended <- system.then(system.now())
          let #(output, next, outcome, recorder) = case outcome {
            record.Completed(#(Some(value), scope)) -> {
              let #(encoded, recorder) = recorder.encode(recorder, value)
              #(
                [Ok(simple_debug.inspect(value))],
                #("", scope, list.append(defs, assignments), state),
                run.Returned(encoded),
                recorder,
              )
            }
            record.Completed(#(None, scope)) -> #(
              [],
              #("", scope, list.append(defs, assignments), state),
              run.Finished,
              recorder,
            )
            record.Raised(#(reason, location, _env, k)) -> {
              let rendered = execute.render_error(reason, location, k, cwd)
              #(
                [Error(rendered)],
                #("", scope, defs, state),
                run.Failed(recorder.redact_text(recorder, rendered)),
                recorder,
              )
            }
            record.Exited(status:) -> #(
              [Error("exited with status " <> int.to_string(status))],
              #("", scope, defs, state),
              run.Exited(status),
              recorder,
            )
          }
          let cell =
            run.Run(
              id: "cell-" <> int.to_string(list.length(recording.events) + 1),
              kind: run.Cell,
              code:,
              origin: run.Repl,
              program: Some(pinned.program),
              lock: recorder.lock_secrets(recorder, pinned.lock),
              cwd:,
              journal: recorder.journal(recorder),
              outcome:,
              started:,
              ended:,
            )
          let recording =
            Recording(..recording, recorder:, events: [
              trace.Execution(cell),
              ..recording.events
            ])
          use saved <- system.then(save(recording))
          let output = case saved {
            Ok(_) -> output
            Error(reason) -> list.append(output, [Error(reason)])
          }
          system.Done(#(output, next, recording))
        }
      }
    }
  }
}

fn save(recording: Recording) {
  let Recording(id:, started:, cwd:, recorder:, events:) = recording
  use ended <- system.then(system.now())
  let session =
    trace.Session(
      id:,
      started:,
      ended:,
      cwd:,
      agent: None,
      events: list.reverse(events),
    )
  traces.save(archive.new(session, recorder.store(recorder)), cwd)
}

pub fn handle(code, scope, defs, state) {
  use #(results, _, next) <- system.map(handle_recorded(
    code,
    scope,
    defs,
    state,
  ))
  #(results, next)
}

/// Also return the EYG effects performed, as `execute.block_recorded` does.
pub fn handle_recorded(code, scope, defs, state) {
  case code {
    "/" <> command -> {
      use #(results, next) <- system.map(handle_meta(
        command,
        scope,
        defs,
        state,
      ))
      #(results, [], next)
    }
    _ -> {
      case parser.block_from_string(code) {
        Ok(#(#(assignments, tail), _)) -> {
          let tail = option.unwrap(tail, #(tree.Vacant, #(0, 0)))
          let source =
            list.fold_right(assignments, tail, fn(acc, assignment) {
              let #(label, value, at) = assignment
              #(tree.Let(label, value, acc), at)
            })
          let located =
            tree.map_annotation(source, fn(span) {
              source.Location(source.Repl, source.Text(code, span))
            })
          evaluate(located, assignments, scope, defs, state)
        }
        Error(UnexpectEnd) ->
          system.Done(#([], [], #(code, scope, defs, state)))
        Error(reason) ->
          system.Done(#(
            [Error(parser.format_error(reason, code))],
            [],
            #("", scope, defs, state),
          ))
      }
    }
  }
}

fn evaluate(code, assignments, scope, defs, state) {
  use cwd <- system.then(system.cwd())
  let cwd = result.unwrap(cwd, "")
  use #(result, state, records) <- system.map(execute.block_recorded(
    code,
    scope,
    state,
  ))
  case result {
    Ok(#(Some(value), scope)) -> #(
      [Ok(simple_debug.inspect(value))],
      records,
      #("", scope, list.append(defs, assignments), state),
    )
    Ok(#(None, scope)) -> #(
      [],
      records,
      #("", scope, list.append(defs, assignments), state),
    )
    Error(#(reason, location, _env, k)) -> #(
      [Error(execute.render_error(reason, location, k, cwd))],
      records,
      #("", scope, defs, state),
    )
  }
}

fn handle_meta(command, scope, defs, state: execute.State) {
  let #(name, argument) = case string.split_once(command, " ") {
    Ok(#(name, argument)) -> #(name, argument)
    Error(Nil) -> #(string.trim(command), "")
  }
  let message = case name {
    "help" -> help_text
    "scope" -> render_scope(scope)
    "type" | "t" -> type_of(argument, defs, cache.types(state.cache))
    "" -> "missing command, try :help"
    _ -> "unknown command :" <> name <> ", try :help"
  }
  system.Done(#([Ok(message)], #("", scope, defs, state)))
}

pub const help_text =
  "shell commands:
  /help            show this message
  /scope           list the variables in scope
  /trace           show the stack trace of the most recent error
  /type <expr>     infer and show the type of an expression
  /t <expr>        alias for /type
an empty line exits the shell"

/// Render the variables in scope, oldest binding first. A name rebound by
/// a later `let` is shown once, at its most recent value.
pub fn render_scope(scope) -> String {
  let #(_, lines) =
    list.fold(scope, #([], []), fn(acc, entry) {
      let #(seen, lines) = acc
      let #(name, value) = entry
      case list.contains(seen, name) {
        True -> acc
        False -> #([name, ..seen], [
          name <> " = " <> simple_debug.inspect(value),
          ..lines
        ])
      }
    })
  case lines {
    [] -> "(no variables in scope)"
    _ -> string.join(lines, "\n")
  }
}

/// Infer and render the type of `argument`. It is type checked wrapped in
/// `defs`, the assignments entered earlier in the session, so it can
/// refer to the variables in scope. `references` supplies the types of
/// any modules already fetched into the cache.
pub fn type_of(argument: String, defs, references) -> String {
  case string.trim(argument) {
    "" -> "usage: :type <expression>"
    argument ->
      case parser.block_from_string(argument) {
        Error(UnexpectEnd) -> "incomplete expression"
        Error(reason) -> parser.format_error(reason, argument)
        Ok(#(#(assignments, tail), _)) -> {
          let tail = option.unwrap(tail, #(tree.Vacant, #(0, 0)))
          let source =
            list.fold_right(
              list.append(defs, assignments),
              tail,
              fn(acc, assignment) {
                let #(label, value, at) = assignment
                #(tree.Let(label, value, acc), at)
              },
            )
          let context = infer.unpure()

          let analysis =
            infer.check_with_references(context, references, source)
          case infer.all_errors(analysis) {
            [] ->
              type_debug.render_type(infer.type_(analysis))
              <> effect_summary(analysis)
            [#(_location, reason), ..] ->
              "type error: " <> type_debug.render_reason(reason)
          }
        }
      }
  }
}

// Effects performed by an expression, shown after the value type as
// `! <Effect, ...>`. The inference context is open (any effect is
// allowed), so a pure expression leaves an unbound effect variable,
// which renders as no effects.
fn effect_summary(analysis: infer.Analysis(_)) -> String {
  let #(_node, #(_result, _type, effect, _scope)) = analysis.tree
  case effect_labels(binding.resolve(effect, analysis.bindings)) {
    [] -> ""
    labels -> " ! <" <> string.join(labels, ", ") <> ">"
  }
}

fn effect_labels(effect) -> List(String) {
  case effect {
    t.EffectExtend(label, _, tail) -> [label, ..effect_labels(tail)]
    _ -> []
  }
}
