//// Every web session is recorded as a Glasshouse session, as the CLI records agents,
//// so it can be downloaded, opened in the Glasshouse debugger and replayed.
////
//// The context is recorded as the configuration run.
//// Tool programs are pinned before they run, each reference is replaced by the module value the session used,
//// stored by content, so a replay needs nothing from the hub.
//// The agent reads the runs of the session so far with the `Trace` effect.

import eyg/analysis/type_/isomorphic as t
import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import glasshouse/archive.{type Archive}
import glasshouse/journal.{type Entry}
import glasshouse/lock
import glasshouse/recorder.{type Recorder}
import glasshouse/run
import glasshouse/session.{type Event, type Generation}
import glasshouse/sha256
import glasshouse/value
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import multiformats/cid/v1
import otel/clock
import touch_grass/interface

pub const label = "Trace"

pub type Trace {
  Trace(
    id: String,
    started: Int,
    recorder: Recorder,
    /// Newest first.
    events: List(Event),
    configured: Bool,
    generations: Int,
  )
}

/// An identifier like the CLI gives sessions, the time it started in UTC.
pub fn new_id(started: Int) -> String {
  let #(date, time) =
    timestamp.from_unix_seconds(started / 1000)
    |> timestamp.to_calendar(calendar.utc_offset)
  let pad = fn(n, width) { string.pad_start(int.to_string(n), width, "0") }
  pad(date.year, 4)
  <> pad(calendar.month_to_int(date.month), 2)
  <> pad(date.day, 2)
  <> "T"
  <> pad(time.hours, 2)
  <> pad(time.minutes, 2)
  <> pad(time.seconds, 2)
  <> "-web"
}

pub fn new(id: String, started: Int) -> Trace {
  Trace(
    id:,
    started:,
    recorder: recorder.new(sha256.hash),
    events: [],
    configured: False,
    generations: 0,
  )
}

/// Separate browser sessions started in the same second, as the CLI does.
pub fn new_session(started: Int) -> Trace {
  let suffix =
    int.to_base36(int.random(4_503_599_627_370_496)) |> string.lowercase
  let id = string.replace(new_id(started), "-web", "-" <> suffix <> "-web")
  new(id, started)
}

fn add(trace: Trace, event: Event) -> Trace {
  Trace(..trace, events: [event, ..trace.events])
}

/// Record the context every run has in scope, once, before the first prompt.
pub fn configure(
  trace: Trace,
  name: String,
  context: state.Value(m),
  at: Int,
) -> Trace {
  case trace.configured {
    True -> trace
    False -> {
      let #(outcome, recorder) = recorder.encode(trace.recorder, context)
      // Replaying the configuration evaluates to the context, as an overlay configuration does.
      let #(program, recorder) =
        recorder.encode(
          recorder,
          v.Record(dict.from_list([#("context", context)])),
        )
      let #(recorder, program) = recorder.store_node(recorder, program)
      let config =
        run.Run(
          id: "config",
          kind: run.Config,
          code: name,
          origin: run.Inline,
          program: Some(program),
          lock: lock.empty(),
          cwd: "/",
          journal: [],
          outcome: run.Returned(outcome),
          started: at,
          ended: at,
        )
      Trace(..trace, recorder:, configured: True)
      |> add(session.Execution(config))
    }
  }
}

pub fn prompt(trace: Trace, at: Int, text: String) -> Trace {
  add(trace, session.Prompt(at:, text:))
}

/// The identifier of the next generation, its tool calls are numbered from it.
pub fn next_generation(trace: Trace) -> String {
  "g" <> int.to_string(trace.generations + 1)
}

pub fn call_id(generation: String, index: Int) -> String {
  generation <> "/" <> int.to_string(index)
}

/// Add the bytes of a request or response body to the store.
pub fn store_body(trace: Trace, body: BitArray) -> #(Trace, String) {
  let #(recorder, cid) = recorder.store_binary(trace.recorder, body)
  #(Trace(..trace, recorder:), cid)
}

pub fn generated(trace: Trace, generation: Generation) -> Trace {
  Trace(..trace, generations: trace.generations + 1)
  |> add(session.Generated(generation))
}

/// Pin a program before it runs, references are replaced by the stored module values from the cache.
pub fn pin(
  trace: Trace,
  source: ir.Node(m),
  cache: cache.Cache(n),
) -> #(Trace, String) {
  let #(recorder, pins) =
    references(source, [])
    |> list.fold(#(trace.recorder, dict.new()), fn(acc, reference) {
      let #(recorder, pins) = acc
      case
        dict.has_key(pins, reference),
        cache.get_reference(cache, reference)
      {
        False, Ok(cache.Module(value: module, ..)) -> {
          let #(encoded, recorder) = recorder.encode(recorder, module)
          let #(recorder, cid) = recorder.store_node(recorder, encoded)
          case v1.from_string(cid) {
            Ok(#(cid, _)) -> #(recorder, dict.insert(pins, reference, cid))
            Error(_) -> #(recorder, pins)
          }
        }
        _, _ -> #(recorder, pins)
      }
    })
  let #(recorder, program) =
    recorder.store_node(recorder, rewrite(source, pins))
  #(Trace(..trace, recorder:), program)
}

fn references(
  node: ir.Node(m),
  found: List(ir.Reference),
) -> List(ir.Reference) {
  case node.0 {
    ir.Reference(reference) -> [reference, ..found]
    ir.Lambda(body:, ..) -> references(body, found)
    ir.Apply(func:, argument:) -> references(argument, references(func, found))
    ir.Let(definition:, body:, ..) ->
      references(body, references(definition, found))
    _ -> found
  }
}

fn rewrite(node: ir.Node(m), pins: Dict(ir.Reference, v1.Cid)) -> ir.Node(m) {
  let #(expression, meta) = node
  let expression = case expression {
    ir.Reference(reference) ->
      case dict.get(pins, reference) {
        Ok(cid) -> ir.Reference(ir.Content(cid))
        Error(Nil) -> expression
      }
    ir.Lambda(label:, body:) -> ir.Lambda(label:, body: rewrite(body, pins))
    ir.Apply(func:, argument:) ->
      ir.Apply(func: rewrite(func, pins), argument: rewrite(argument, pins))
    ir.Let(label:, definition:, body:) ->
      ir.Let(
        label:,
        definition: rewrite(definition, pins),
        body: rewrite(body, pins),
      )
    _ -> expression
  }
  #(expression, meta)
}

/// Record one answered effect, the entry belongs to the run that performed it.
pub fn effect(
  trace: Trace,
  label: String,
  lift: state.Value(m),
  reply: state.Value(m),
  started: Int,
  ended: Int,
) -> #(Trace, Entry) {
  answer(trace, label, lift, reply, journal.Performed, started, ended)
}

pub fn answer(
  trace: Trace,
  label: String,
  lift: state.Value(m),
  reply: state.Value(m),
  answer: journal.Answer,
  started: Int,
  ended: Int,
) -> #(Trace, Entry) {
  let #(lift, recorder) = recorder.encode(trace.recorder, lift)
  let #(reply, recorder) = recorder.encode(recorder, reply)
  let entry =
    journal.Entry(
      label:,
      lift:,
      reply:,
      answer:,
      path: None,
      started:,
      duration: ended - started,
    )
  #(Trace(..trace, recorder:), entry)
}

/// A finished tool call, its run and the result returned to the model.
pub fn tool_call(
  trace: Trace,
  id: String,
  code: String,
  program: Option(String),
  journal: List(Entry),
  outcome: run.Outcome,
  started: Int,
  ended: Int,
  result: String,
) -> Trace {
  let run =
    run.Run(
      id:,
      kind: run.Tool(id),
      code:,
      origin: run.Inline,
      program:,
      lock: lock.empty(),
      cwd: "/",
      journal:,
      outcome:,
      started:,
      ended:,
    )
  trace
  |> add(session.Execution(run))
  |> add(session.ToolResult(at: ended, call_id: id, text: result))
}

/// The outcome of a value returned by a tool program.
pub fn returned(trace: Trace, value: state.Value(m)) -> #(Trace, run.Outcome) {
  let #(encoded, recorder) = recorder.encode(trace.recorder, value)
  #(Trace(..trace, recorder:), run.Returned(encoded))
}

pub fn session(
  trace: Trace,
  agent: session.Agent,
  ended: Int,
) -> session.Session {
  session.Session(
    id: trace.id,
    started: trace.started,
    ended:,
    cwd: "/",
    agent: Some(agent),
    events: list.reverse(trace.events),
  )
}

/// The session as an archive, ready to save.
pub fn archive(trace: Trace, agent: session.Agent, ended: Int) -> Archive {
  archive.new(session(trace, agent, ended), recorder.store(trace.recorder))
}

/// The interface of the `Trace` effect, so programs that use it are type checked.
pub fn interface() -> interface.Interface(eff, meta) {
  interface.Interface(
    name: label,
    lift_type: t.unit,
    lower_type: t.List(
      t.record([
        #("call", t.String),
        #("code", t.String),
        #(
          "effects",
          t.List(
            t.record([
              #("label", t.String),
              #("request", t.String),
              #("reply", t.String),
            ]),
          ),
        ),
        #("result", t.String),
      ]),
    ),
    decode: fn(lift) { Error(break.UnhandledEffect(label, lift)) },
  )
}

/// Every tool call so far, oldest first, with each effect and the result the model read.
pub fn reply(trace: Trace) -> state.Value(m) {
  let store = recorder.store(trace.recorder)
  let events = list.reverse(trace.events)
  let results =
    list.filter_map(events, fn(event) {
      case event {
        session.ToolResult(call_id:, text:, ..) -> Ok(#(call_id, text))
        _ -> Error(Nil)
      }
    })
  list.filter_map(events, fn(event) {
    case event {
      session.Execution(run: run.Run(kind: run.Tool(id), code:, journal:, ..)) ->
        Ok(
          v.Record(
            dict.from_list([
              #("call", v.String(id)),
              #("code", v.String(code)),
              #(
                "effects",
                v.LinkedList(
                  list.map(journal, fn(entry) {
                    v.Record(
                      dict.from_list([
                        #("label", v.String(entry.label)),
                        #(
                          "request",
                          v.String(value.summary(entry.lift, store, 2000)),
                        ),
                        #(
                          "reply",
                          v.String(value.summary(entry.reply, store, 2000)),
                        ),
                      ]),
                    )
                  }),
                ),
              ),
              #(
                "result",
                v.String(case list.key_find(results, id) {
                  Ok(text) -> text
                  Error(Nil) -> ""
                }),
              ),
            ]),
          ),
        )
      _ -> Error(Nil)
    }
  })
  |> v.LinkedList
}

pub fn now() -> Int {
  let time = clock.now()
  time.seconds * 1000 + time.nanoseconds / 1_000_000
}
