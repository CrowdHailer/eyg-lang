//// A small agent session used by several tests.

import eyg/interpreter/value as v
import glasshouse/helpers.{sha256}
import glasshouse/journal
import glasshouse/lock
import glasshouse/recorder
import glasshouse/run
import glasshouse/session
import glasshouse/store
import glasshouse/value
import gleam/dict
import gleam/option.{None, Some}

pub const readme = "# Project\nRead the notes before answering.\n"

pub const notes_before = "line one\nline two\nline three\n"

pub const notes_after = "line one\nline 2\nline three\nline four\n"

fn read_request(path) {
  v.Record(
    dict.from_list([
      #("path", v.String(path)),
      #("offset", v.Integer(0)),
      #("limit", v.Integer(1_000_000)),
    ]),
  )
}

fn write_request(path, contents) {
  v.Record(
    dict.from_list([
      #("path", v.String(path)),
      #("contents", v.Binary(<<contents:utf8>>)),
    ]),
  )
}

/// A session where the config reads a readme,
/// then a tool call reads a file and writes a new version of it.
pub fn session() -> #(session.Session, store.Store) {
  let config_recorder =
    recorder.new(sha256)
    |> recorder.with_threshold(8)
    |> recorder.record(
      "ReadFile",
      read_request("./README.md"),
      v.ok(v.Binary(<<readme:utf8>>)),
      journal.Performed,
      Some("/project/README.md"),
      1000,
      1,
    )
  let #(config_recorder, config_source) =
    recorder.store_binary(config_recorder, <<"let readme = ...":utf8>>)
  let config =
    run.Run(
      id: "config",
      kind: run.Config,
      code: "let readme = ...",
      origin: run.File("/project/.overlay.eyg"),
      program: Some(config_source),
      lock: lock.empty(),
      cwd: "/project",
      journal: recorder.journal(config_recorder),
      outcome: run.Returned(value.encode(v.unit())),
      started: 1000,
      ended: 1002,
    )

  let tool_recorder =
    config_recorder
    |> recorder.restart
    |> recorder.record(
      "ReadFile",
      read_request("notes.txt"),
      v.ok(v.Binary(<<notes_before:utf8>>)),
      journal.Gated,
      Some("/project/notes.txt"),
      2000,
      1,
    )
    |> recorder.record(
      "WriteFile",
      write_request("notes.txt", notes_after),
      v.ok(v.unit()),
      journal.Gated,
      Some("/project/notes.txt"),
      2001,
      1,
    )
    |> recorder.record(
      "StandardOut",
      v.String("updated notes\n"),
      v.unit(),
      journal.Gated,
      None,
      2002,
      0,
    )
  let tool =
    run.Run(
      id: "g1/0",
      kind: run.Tool("g1/0"),
      code: "perform WriteFile(...)",
      origin: run.Inline,
      program: None,
      lock: lock.empty(),
      cwd: "/project",
      journal: recorder.journal(tool_recorder),
      outcome: run.Returned(value.encode(v.String("done"))),
      started: 2000,
      ended: 2003,
    )

  let #(store, request) =
    store.put_binary(
      recorder.store(tool_recorder),
      <<"{\"model\":\"m\"}":utf8>>,
      sha256,
    )
  let #(store, response) =
    store.put_binary(store, <<"{\"message\":{}}":utf8>>, sha256)
  let generation = fn(id, content, calls, usage) {
    session.Generation(
      id:,
      started: 1500,
      ended: 1600,
      key: "key-" <> id,
      request:,
      response: Some(response),
      status: 200,
      thinking: "",
      content:,
      tool_calls: calls,
      usage:,
      source: session.Live,
      error: None,
    )
  }
  let session =
    session.Session(
      id: "session-1",
      started: 1000,
      ended: 3000,
      cwd: "/project",
      agent: Some(session.Agent(
        provider: "ollama",
        model: "test-model",
        system_prompt: "You are helpful.\n" <> readme,
      )),
      events: [
        session.Execution(config),
        session.Prompt(at: 1400, text: "number the second line"),
        session.Generated(generation(
          "g1",
          "",
          [session.ToolCall("g1/0", "run", "{\"code\":\"...\"}")],
          session.Usage(120, 30),
        )),
        session.Execution(tool),
        session.ToolResult(at: 2003, call_id: "g1/0", text: "done"),
        session.Generated(generation(
          "g2",
          "I numbered the line.",
          [],
          session.Usage(180, 10),
        )),
      ],
    )
  #(session, store)
}

/// A session with one block run of the given journal.
pub fn single_run(journal) -> session.Session {
  let run =
    run.Run(
      id: "run",
      kind: run.Block,
      code: "",
      origin: run.Inline,
      program: None,
      lock: lock.empty(),
      cwd: "/",
      journal:,
      outcome: run.Finished,
      started: 0,
      ended: 0,
    )
  session.Session(
    id: "single",
    started: 0,
    ended: 0,
    cwd: "/",
    agent: None,
    events: [session.Execution(run)],
  )
}
