import eyg/cli/helpers
import eyg/cli/inspect
import eyg/cli/record
import eyg/cli/replay
import glasshouse/archive
import glasshouse/journal
import glasshouse/run
import glasshouse/session
import glasshouse/timeline
import gleam/bit_array
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/string
import loam/sandbox
import loam/sandbox/fs
import loam/source

const main =
  "let helper = import \"./helper.eyg\"
let read = (path) -> {
  match perform ReadFile({path, offset: 0, limit: 1000}) {
    Ok(bytes) -> { match !string_from_binary(bytes) { Ok(text) -> { text } Error(_) -> { \"\" } } }
    Error(reason) -> { reason }
  }
}
let notes = read(\"notes.txt\")
let _ = perform WriteFile({path: \"notes.txt\", contents: !string_to_binary(!string_append(notes, helper.line))})
{script: (args) -> { !list_fold(args, 0, (_, n) -> { !int_add(n, 1) }) }}"

fn project() {
  sandbox.sandbox()
  |> sandbox.with_cwd("/project")
  |> sandbox.with_env("EYG_TRACE_DIR", "/traces")
  |> sandbox.with_now(1_791_889_260_000)
  |> sandbox.with_random_values([42])
  |> sandbox.with_files([
    #("/project/main.eyg", main),
    #("/project/helper.eyg", "{line: \"line three\\n\"}"),
    #("/project/notes.txt", "line one\nline two\n"),
  ])
}

fn saved(sandbox: sandbox.Sandbox(_)) {
  let assert Ok(fs.Directory(children:, ..)) =
    fs.inspect(sandbox.file_system, "/traces")
  let assert [name] = dict.keys(children)
  let assert Ok(bytes) = fs.read_bits(sandbox.file_system, "/traces/" <> name)
  let assert Ok(text) = bit_array.to_string(bytes)
  let assert Ok(archive) = archive.from_string(text)
  #("/traces/" <> name, archive)
}

pub fn record_a_script_test() {
  let assert #(sandbox.Returned(Ok(2)), sandbox) =
    record.execute(
      source.File("main.eyg"),
      record.Script(["a", "b"]),
      helpers.config,
    )
    |> sandbox.run(project())
  assert fs.read(sandbox.file_system, "/project/notes.txt")
    == Ok("line one\nline two\nline three\n")
  let #(path, archive) = saved(sandbox)
  assert string.starts_with(path, "/traces/20261013T")
  let assert [session.Execution(run)] = archive.session.events
  assert run.kind == run.Script(["a", "b"])
  assert run.origin == run.File("/project/main.eyg")
  assert list.map(run.journal, fn(e) { e.label }) == ["ReadFile", "WriteFile"]
  assert list.all(run.journal, fn(e) { e.answer == journal.Performed })
  assert dict.has_key(run.lock.files, "/project/helper.eyg")
  assert archive.missing(archive) == []
  assert list.any(sandbox.stderr, fn(line) {
    string.contains(line, "trace saved to /traces/")
  })
}

pub fn replay_a_recorded_script_test() {
  let assert #(sandbox.Returned(Ok(2)), sandbox) =
    record.execute(
      source.File("main.eyg"),
      record.Script(["a", "b"]),
      helpers.config,
    )
    |> sandbox.run(project())
  let #(path, _) = saved(sandbox)
  // The files change after recording, the replay only uses the trace.
  let sandbox =
    sandbox
    |> sandbox.with_file("/project/notes.txt", "changed")
    |> sandbox.with_file("/project/helper.eyg", "{line: \"other\"}")
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    replay.execute(path, helpers.config)
    |> sandbox.run(sandbox)
  let assert [output, ..] = sandbox.stdout
  assert string.contains(output, "✓ script main.eyg")
  assert string.contains(output, "2 effects")
}

pub fn replay_reports_a_tampered_trace_test() {
  let assert #(sandbox.Returned(Ok(2)), sandbox) =
    record.execute(
      source.File("main.eyg"),
      record.Script(["a", "b"]),
      helpers.config,
    )
    |> sandbox.run(project())
  let #(path, archive) = saved(sandbox)
  let assert [session.Execution(run)] = archive.session.events
  let assert [read, ..] = run.journal
  let tampered = run.Run(..run, journal: [read])
  let archive =
    archive.Archive(
      ..archive,
      session: session.Session(..archive.session, events: [
        session.Execution(tampered),
      ]),
    )
  let sandbox = sandbox.with_file(sandbox, path, archive.to_string(archive))
  let assert #(sandbox.Returned(Ok(1)), sandbox) =
    replay.execute(path, helpers.config)
    |> sandbox.run(sandbox)
  let assert [output, ..] = sandbox.stdout
  assert string.contains(output, "✗ script main.eyg")
  assert string.contains(output, "was not recorded: WriteFile")
}

pub fn record_inline_block_test() {
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    record.execute(
      source.Code("perform StandardOut(\"hi\")"),
      record.Block,
      helpers.config,
    )
    |> sandbox.run(project())
  assert list.contains(sandbox.stdout, "hi")
  let #(_, archive) = saved(sandbox)
  let assert [session.Execution(run)] = archive.session.events
  assert run.origin == run.Inline
  assert run.kind == run.Block
}

pub fn failed_runs_are_recorded_test() {
  let assert #(sandbox.Returned(Error(reason)), sandbox) =
    record.execute(
      source.Code("perform Abort(\"stop\")"),
      record.Block,
      helpers.config,
    )
    |> sandbox.run(project())
  assert string.contains(reason, "stop")
  let #(_, archive) = saved(sandbox)
  let assert [session.Execution(run.Run(outcome: run.Failed(_), ..))] =
    archive.session.events
}

pub fn inspect_timeline_and_step_test() {
  let assert #(sandbox.Returned(Ok(2)), sandbox) =
    record.execute(
      source.File("main.eyg"),
      record.Script(["a", "b"]),
      helpers.config,
    )
    |> sandbox.run(project())
  let #(path, archive) = saved(sandbox)
  let frames = timeline.frames(archive.session, archive.store)
  let text = inspect.timeline_text(archive.session, frames, archive.store)
  assert string.contains(text, "ReadFile      notes.txt")
  assert string.contains(text, "WriteFile     notes.txt  +1 -0")
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    inspect.execute(path, Some(1), helpers.config)
    |> sandbox.run(sandbox)
  let assert [output, ..] = sandbox.stdout
  assert string.contains(output, "effect 1 WriteFile in script main.eyg")
  assert string.contains(output, "+line three")
  assert string.contains(output, "notes.txt")
  assert string.contains(output, "(changed)")
  let assert #(sandbox.Returned(Error(reason)), _) =
    inspect.execute(path, Some(9), helpers.config)
    |> sandbox.run(sandbox)
  assert reason == "there is no step 9, the trace has 2 effects"
}

// The length of the secret depends on its value, a dummy can not reproduce it.
const secret_program =
  "let token = match perform Env(\"GITHUB_TOKEN\") {
  Some(token) -> { token }
  None(_) -> { \"\" }
}
perform StandardOut(!int_to_string(!string_length(token)))"

fn secret_project() {
  project()
  |> sandbox.with_env("GITHUB_TOKEN", "ghp_real_token")
}

pub fn secrets_are_locked_by_hash_test() {
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    record.execute(source.Code(secret_program), record.Block, helpers.config)
    |> sandbox.run(secret_project())
  let #(path, archive) = saved(sandbox)
  let assert [session.Execution(run)] = archive.session.events
  let assert Ok(_) = dict.get(run.lock.secrets, "env:GITHUB_TOKEN")
  let assert Ok(text) = fs.read(sandbox.file_system, path)
  assert !string.contains(text, "ghp_real_token")
  // The same secret is used for the replay.
  let assert #(sandbox.Returned(Ok(0)), sandbox) =
    replay.execute(path, helpers.config)
    |> sandbox.run(sandbox)
  let assert [output, ..] = sandbox.stdout
  assert string.contains(output, "secret env:GITHUB_TOKEN is the one recorded")
  // A changed secret is not used, the program asks for different output.
  let sandbox = sandbox.with_env(sandbox, "GITHUB_TOKEN", "other")
  let assert #(sandbox.Returned(Ok(1)), sandbox) =
    replay.execute(path, helpers.config)
    |> sandbox.run(sandbox)
  let assert [output, ..] = sandbox.stdout
  assert string.contains(
    output,
    "secret env:GITHUB_TOKEN has changed since the recording, a dummy is used",
  )
}
