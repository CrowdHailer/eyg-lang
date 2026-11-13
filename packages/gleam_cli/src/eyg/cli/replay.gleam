//// Rerun every run in a trace and check it reproduces exactly.
////
//// Effects are answered from the journal, so nothing outside the archive is touched.
//// Secret modules are never in an archive, a local copy is used when its CID matches the lock.
//// Mounted secrets are not either, a local secret is used when its hash matches the lock, otherwise a dummy.

import eyg/cli/internal/config
import eyg/cli/internal/terminal
import eyg/cli/internal/traces
import glasshouse/archive
import glasshouse/lock
import glasshouse/recorder
import glasshouse/rerun
import glasshouse/run
import glasshouse/secret.{type Secret, Secret}
import glasshouse/session
import glasshouse/store.{type Store}
import glasshouse/timeline
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam_community/ansi
import loam/pin
import loam/secrets
import loam/source
import loam/system

pub fn execute(
  path: String,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use archive <- system.then(traces.load(path))
  use archive <- system.try(archive)
  let archive.Archive(session:, store:, ..) = archive
  use store <- system.then(recover_secret_modules(session, store, config))
  use #(known, notes) <- system.then(local_secrets(session))
  let reports = rerun.session_with_secrets(session, store, known)
  let lines =
    list.map(reports, fn(report) {
      describe(report, session.cwd, store, config.styled)
    })
    |> list.append(notes, _)
  let header =
    "replaying "
    <> session.id
    <> " ("
    <> plural(list.length(reports), "run")
    <> ")"
  let footer = generations_summary(session)
  use Nil <- system.then(
    system.stdout(string.join([header, ..list.append(lines, footer)], "\n")),
  )
  case list.all(reports, fn(report) { report.problem == None }) {
    True -> system.Done(Ok(0))
    False -> system.Done(Ok(1))
  }
}

fn describe(report: rerun.Report, cwd, store, styled) {
  let rerun.Report(run:, effects:, problem:) = report
  let name = run_name(run, cwd)
  let count = plural(effects, "effect")
  case problem {
    None ->
      terminal.style(styled, ansi.green, "✓ ")
      <> string.pad_end(name, 32, " ")
      <> " "
      <> count
    Some(problem) ->
      terminal.style(styled, ansi.red, "✗ ")
      <> string.pad_end(name, 32, " ")
      <> " "
      <> rerun.describe(problem, store)
  }
}

pub fn plural(count: Int, word: String) -> String {
  int.to_string(count)
  <> " "
  <> word
  <> case count {
    1 -> ""
    _ -> "s"
  }
}

/// A short description of a run, i.e. `tool call g1/0`.
pub fn run_name(run: run.Run, cwd: String) -> String {
  let detail = case run.kind, run.origin {
    run.Tool(call_id:), _ -> call_id
    _, run.File(path:) -> timeline.relative(path, cwd)
    _, run.Inline -> "inline code"
    _, run.Stdin -> "stdin"
    _, run.Repl -> "repl"
  }
  run.kind_to_string(run.kind) <> " " <> detail
}

fn generations_summary(session: session.Session) {
  case session.generations(session) {
    [] -> []
    generations -> {
      let #(live, recorded) = session.usage(session)
      [
        int.to_string(list.length(generations))
        <> " generations in the trace, "
        <> int.to_string(live.input + recorded.input)
        <> " tokens in and "
        <> int.to_string(live.output + recorded.output)
        <> " out, their replies are taken from the archive",
      ]
    }
  }
}

/// Secrets the runs knew with a local copy that has the hash the lock recorded,
/// with a note for each secret saying how it is replayed.
fn local_secrets(
  session: session.Session,
) -> system.Effect(#(List(Secret), List(String))) {
  session.runs(session)
  |> list.flat_map(fn(run) { dict.to_list(run.lock.secrets) })
  |> list.unique
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> system.fold(#([], []), fn(acc, entry) {
    let #(known, notes) = acc
    let #(name, digest) = entry
    use value <- system.map(case name {
      "env:" <> variable -> {
        use value <- system.map(system.env(variable))
        option.to_result(value, Nil) |> result.replace_error("")
      }
      _ -> secrets.mount(name)
    })
    case value {
      Ok(value) ->
        case recorder.digest(traces.sha256, value) == digest {
          True -> #([Secret(name:, value:), ..known], [
            "  secret " <> name <> " is the one recorded",
            ..notes
          ])
          False -> #(known, [
            "  secret "
              <> name
              <> " has changed since the recording, a dummy is used",
            ..notes
          ])
        }
      Error(_) -> #(known, [
        "  secret " <> name <> " is not available here, a dummy is used",
        ..notes
      ])
    }
  })
  |> system.map(fn(acc) { #(acc.0, list.reverse(acc.1)) })
}

/// Add secret modules, never stored in archives, from local files when they still match the lock.
fn recover_secret_modules(
  session: session.Session,
  store: Store,
  config: config.Config,
) -> system.Effect(Store) {
  let secrets =
    session.runs(session)
    |> list.flat_map(fn(run) { dict.to_list(run.lock.files) })
    |> list.filter(fn(file) {
      let #(path, lock.File(module:, ..)) = file
      pin.is_secret(path) && !store.has(store, module)
    })
    |> list.unique
  system.fold(secrets, store, fn(store, file) {
    let #(path, lock.File(module:, ..)) = file
    use code <- system.then(system.read_file(path))
    case code {
      Error(_) -> system.Done(store)
      Ok(code) ->
        case source.parse(code, source.Disk(path)) {
          Error(_) -> system.Done(store)
          Ok(parsed) -> {
            let state = config.state(config)
            let recorder = recorder.new(traces.sha256)
            use #(pinned, _, recorder) <- system.map(pin.pin(
              parsed,
              "/",
              state,
              recorder,
              pin.allow,
            ))
            case pinned {
              Ok(pin.Pinned(program:, ..)) if program == module ->
                store.merge(store, recorder.store(recorder))
              _ -> store
            }
          }
        }
    }
  })
}
