//// Run a program and save a trace of everything it did.
////
//// The program is pinned before it runs, every effect it performs is recorded,
//// and the session is saved as an archive that `eyg replay` can reproduce.

import eyg/cli/internal/config
import eyg/cli/internal/traces
import eyg/cli/script
import eyg/interpreter/cast
import eyg/interpreter/state
import glasshouse/archive
import glasshouse/recorder.{type Recorder}
import glasshouse/run
import glasshouse/session
import gleam/option.{None, Some}
import loam/execute
import loam/pin
import loam/record
import loam/source
import loam/system

pub type Mode {
  /// Run a block, as `eyg run`.
  Block
  /// Call the `script` field with arguments, as `eyg script`.
  Script(arguments: List(String))
}

pub fn execute(
  input: source.Input,
  mode: Mode,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use input <- system.try(source.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))
  use started <- system.then(system.now())
  use id <- system.then(traces.new_id(started))

  let state = config.state(config)
  let recorder = recorder.new(traces.sha256)
  use #(pinned, _state, recorder) <- system.then(pin.pin(
    source,
    cwd,
    state,
    recorder,
    pin.allow,
  ))
  use pinned <- system.try(pinned)

  let #(kind, runnable) = case mode {
    Block -> #(run.Block, source)
    Script(arguments:) -> #(
      run.Script(arguments),
      script.call(source, arguments),
    )
  }
  use #(outcome, recorder, Nil) <- system.then(record.run_block(
    runnable,
    [],
    pinned,
    cwd,
    recorder,
    record.computer,
    Nil,
  ))
  use ended <- system.then(system.now())
  let #(recorded, exit, recorder) =
    conclude(outcome, mode, recorder, cwd, source.1)

  let run =
    run.Run(
      id:,
      kind:,
      code:,
      origin: origin(input),
      program: Some(pinned.program),
      lock: recorder.lock_secrets(recorder, pinned.lock),
      cwd:,
      journal: recorder.journal(recorder),
      outcome: recorded,
      started:,
      ended:,
    )
  let session =
    session.Session(id:, started:, ended:, cwd:, agent: None, events: [
      session.Execution(run),
    ])
  use saved <- system.then(traces.save(
    archive.new(session, recorder.store(recorder)),
    cwd,
  ))
  use path <- system.try(saved)
  use Nil <- system.then(system.write_stderr("trace saved to " <> path <> "\n"))
  system.Done(exit)
}

/// The recorded outcome and the exit code of the command.
pub fn conclude(
  outcome: record.Outcome(#(option.Option(execute.Value), execute.Scope)),
  mode: Mode,
  recorder: Recorder,
  cwd: String,
  location: source.Location,
) -> #(run.Outcome, Result(Int, String), Recorder) {
  case outcome {
    record.Completed(#(Some(value), _)) -> {
      let #(encoded, recorder) = recorder.encode(recorder, value)
      let exit = case mode {
        Block -> Ok(0)
        Script(..) ->
          case cast.as_integer(value) {
            Ok(status) -> Ok(status)
            Error(reason) ->
              Error(execute.render_error(reason, location, state.Empty, cwd))
          }
      }
      #(run.Returned(encoded), exit, recorder)
    }
    record.Completed(#(None, _)) -> #(run.Finished, Ok(0), recorder)
    record.Raised(#(reason, location, _, k)) -> {
      let rendered = execute.render_error(reason, location, k, cwd)
      #(
        run.Failed(recorder.redact_text(recorder, rendered)),
        Error(rendered),
        recorder,
      )
    }
    record.Exited(status:) -> #(run.Exited(status), Ok(status), recorder)
  }
}

fn origin(input: source.Input) -> run.Origin {
  case input {
    source.File(path:) -> run.File(path)
    source.Code(..) -> run.Inline
    source.Stdin -> run.Stdin
  }
}
