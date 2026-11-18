//// Run code in a session so that it can be resumed from the session's history.
////
//// Code runs in the session's process, from the latest root of the box, until it finishes, makes a request or sleeps.
//// The events of that segment are appended to the session's thread, then the files it changed are merged into the box,
//// then the request or sleep starts. A segment that only read files never waits for the box process.
//// A change that conflicts or does not type check is rejected and the request is not made.
//// The code continues from the box's latest root with the rejection as its answer, code fails with it
//// and a chat tells the llm, which can repair the change.
//// The response is recorded as soon as it is received and the code continues from the latest root.
////
//// If the process stops, the code is replayed with the recorded answers the next time the session is used.
//// If the events of the last segment were recorded its change is merged again, which does nothing if it was merged,
//// then the request or sleep is made. A request is sent again if it is GET or HEAD,
//// any other request is answered with a network error as it might have been received.
////
//// A message to a session that chats with an llm is a turn that runs the code of each tool call the llm makes.
//// Asking the llm for a completion is a stop like a request, the completion is recorded as soon as it is received.
//// Completions have no effect outside the session, so one that was asked for but not recorded is asked for again.
//// Messages sent to the chat while the llm's tool calls run are recorded with the next completion they are added to.
////
//// Each turn records the policy it runs with and the module each package reference resolved to,
//// so a replay runs the same code after the policy changes or a package is released.
//// Code reads the secrets of its box. Secrets are never recorded, a fingerprint of each secret read is recorded instead.
//// If a secret changed the turn cannot be replayed and fails saying which secret changed.

import cloud/apex/context.{type Context, Context}
import cloud/beam/execute
import cloud/box
import cloud/data/db
import cloud/data/sessions.{type Session}
import cloud/data/thread
import cloud/live
import cloud/overlay
import cloud/registry
import cloud/sessions/event.{type Event}
import cloud/stream
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/erlang/process
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import overlay/llm/chat
import pog
import unixfs/mfs

/// What a turn came to and everything it printed.
pub type Outcome =
  #(Result(String, String), List(String))

type Segment =
  fn(execute.State, v1.Cid) -> execute.Run(String)

type Resume =
  fn(execute.Answer, execute.State, v1.Cid) -> execute.Run(String)

// What happens after a segment's change is merged.
type Next {
  Return(outcome: Result(String, String), output: List(String), root: v1.Cid)
  Perform(execute.Wait, Resume)
  // Answer without performing, for a request that might have been received.
  Reply(execute.Answer, Resume)
}

// Where a segment of code stops.
type Stop {
  Stopped(
    state: execute.State,
    outcome: Result(String, String),
    root: v1.Cid,
    output: List(String),
  )
  // A request or sleep is done outside the box process, `left` is the event that records it.
  Leaving(
    state: execute.State,
    wait: execute.Wait,
    left: Event,
    root: v1.Cid,
    resume: Resume,
  )
}

/// What is sent to a session.
pub type Input {
  Code(String)
  /// A program built in a structural editor.
  Program(ir.Node(Nil))
  /// A message for the session's llm.
  Message(String)
}

/// A new session in the box, it chats with the llm configured as `llm` if there is one.
pub fn start(
  context: Context,
  box: String,
  llm: Option(String),
) -> Result(Session, box.Reason) {
  case llm {
    None -> create(context, box, [], [])
    Some(llm) ->
      case dict.has_key(context.llms, llm) {
        True -> create(context, box, [], [event.Configured(llm)])
        False -> Error(box.Invalid(["No llm is configured as " <> llm]))
      }
  }
}

/// A new session in the box whose history is `events`, events already in the thread are shared.
/// The box is made durable if it is only in memory.
/// `times` are when each event was first recorded, leave them out for new events.
pub fn create(
  context: Context,
  box: String,
  times: List(Int),
  events: List(Event),
) -> Result(Session, box.Reason) {
  let payloads =
    list.map(events, fn(event) { json.to_string(event.encode(event)) })
  let nodes = thread.nodes(None, payloads)
  let head =
    list.last(nodes) |> result.map(fn(node) { node.key }) |> option.from_result
  // A box is only kept in memory until a session is made in it.
  use Nil <- result.try(box.durable(context, box))
  db.transaction(context.db, fn(connection) {
    use _ <- result.try(case times {
      [] -> db.execute(thread.insert(nodes), connection)
      _ -> db.execute(thread.restore(list.zip(times, nodes)), connection)
    })
    use created <- result.map(db.execute(sessions.create(box, head), connection))
    let assert [session] = created.rows
    session
  })
  |> result.map_error(fn(error) { box.Failed(string.inspect(error)) })
}

pub fn find(context: Context, id: String) -> Result(Session, box.Reason) {
  case db.execute(sessions.get(id), context.db) {
    Ok(pog.Returned(rows: [session], ..)) -> Ok(session)
    Ok(_) -> Error(box.Missing)
    Error(reason) -> Error(box.Failed(string.inspect(reason)))
  }
}

/// The most recent sessions in any box, with the name of the box if it has one.
/// Sessions in transient boxes are left out unless `transient` is true.
pub fn recent(
  context: Context,
  limit: Int,
  transient: Bool,
) -> Result(List(#(Session, Option(String))), box.Reason) {
  db.execute(sessions.recent(limit, transient), context.db)
  |> result.map(fn(returned) { returned.rows })
  |> result.map_error(fn(reason) { box.Failed(string.inspect(reason)) })
}

/// Whether the last turn in the events has not finished.
pub fn unfinished_turn(events: List(Event)) -> Bool {
  list.map(events, fn(event) { #("", event) }) |> unfinished |> result.is_ok
}

/// Run a turn in the session's process, which runs one turn at a time.
pub fn send(
  context: Context,
  session: Session,
  input: Input,
) -> Result(Outcome, box.Reason) {
  in_process(context, session, fn() { run(context, session, input) })
}

/// Finish the last turn if it is unfinished, after a turn that is running finishes.
pub fn resume(context: Context, session: Session) -> Result(Nil, box.Reason) {
  use <- in_process(context, session)
  use context <- result.try(in_box(context, session.box))
  recover(context, session)
}

fn in_process(context: Context, session: Session, then) {
  registry.lookup(context.sessions, session.id, fn() { registry.serve(Nil) })
  |> registry.call(600_000, fn(_) { #(Nil, then()) })
}

/// Stop a turn that is running and record it as finished with an error, so it is not resumed.
/// Changes that were merged are kept, a change that was waiting to be merged is not merged.
pub fn cancel(context: Context, session: Session) -> Result(Nil, box.Reason) {
  let process =
    registry.lookup(context.sessions, session.id, fn() { registry.serve(Nil) })
  case process.subject_owner(process) {
    Ok(pid) -> {
      let monitor = process.monitor(pid)
      process.kill(pid)
      let _ =
        process.new_selector()
        |> process.select_specific_monitor(monitor, fn(_) { Nil })
        |> process.selector_receive(5000)
      Nil
    }
    Error(Nil) -> Nil
  }
  use history <- result.try(history(context, session.id))
  case unfinished(list.map(history, fn(entry) { #(entry.1, entry.2) })) {
    Error(Nil) -> Ok(Nil)
    Ok(_) -> {
      use box <- result.try(box.latest(context, session.box))
      let cancelled = event.Finished(Error("cancelled"), [], box.root)
      record(context, session, [cancelled]) |> result.replace(Nil)
    }
  }
}

/// Run a turn in the session, an unfinished turn is finished first.
pub fn run(
  context: Context,
  session: Session,
  input: Input,
) -> Result(Outcome, box.Reason) {
  use context <- result.try(in_box(context, session.box))
  use Nil <- result.try(recover(context, session))
  let state = execute.State(..context.state, pins: dict.new())
  let #(policy, state) = execute.load_policy(context.policy, state)
  use policy <- result.try(
    result.map_error(policy, fn(reason) { box.Failed("policy " <> reason) }),
  )
  let stored = mfs.File(<<context.policy:utf8>>)
  use Nil <- result.try(
    execute.files(mfs.Put(stored, mfs.Done), state)
    |> result.replace(Nil)
    |> result.map_error(box.Failed),
  )
  let stored = mfs.identify(stored).cid
  use #(started, segment) <- result.try(case input {
    Code(code) -> Ok(#(event.Started(code, stored), program(policy, code)))
    Program(source) ->
      Ok(#(event.Submitted(source, stored), built(policy, source)))
    Message(message) -> {
      use history <- result.try(history(context, session.id))
      let before = list.map(history, fn(entry) { #(entry.1, entry.2) })
      chat(context, state, before, policy, message)
      |> result.map(fn(segment) { #(event.Sent(message, stored), segment) })
      |> result.map_error(fn(reason) { box.Invalid([reason]) })
    }
  })
  let events = [started, ..pinned(dict.new(), state)]
  use _ <- result.try(record(context, session, events))
  drive(context, session, state, segment)
}

fn program(policy, code) -> Segment {
  fn(state, root) { execute.block(code, state, policy, root, fn(_) { Nil }) }
}

fn built(policy, source) -> Segment {
  fn(state, root) {
    execute.program(source, state, policy, root, fn(_) { Nil })
  }
}

// The llm replies to the message, after the chat in the events before it.
fn chat(context: Context, state: execute.State, before, policy, message) {
  case before {
    [#(_, event.Configured(name)), ..] ->
      case dict.get(context.llms, name) {
        Ok(llm) -> {
          let provider = overlay.box_context(state.origin)
          let history = conversation(list.map(before, fn(entry) { entry.1 }))
          Ok(fn(state, root) {
            overlay.reply(llm, provider, history, message, policy, state, root)
          })
        }
        Error(Nil) -> Error("the llm " <> name <> " is not configured")
      }
    _ -> Error("the session does not chat with an llm")
  }
}

/// The messages the llm was sent and the completions it answered with, oldest first.
/// A chat turn that failed is followed by a message saying why, the llm was not told during the turn.
pub fn conversation(events: List(Event)) -> chat.History {
  let #(reversed, _) =
    list.fold(events, #([], False), fn(acc, event) {
      let #(history, chatting) = acc
      case event, chatting {
        event.Sent(..), _ -> #(history, True)
        event.Started(..), _ | event.Submitted(..), _ -> #(history, False)
        event.Asked(messages, _), _ -> #(
          list.append(list.reverse(messages), history),
          chatting,
        )
        event.Answered(execute.Completed(Ok(completion))), _ -> #(
          [chat.from_completion(completion), ..history],
          chatting,
        )
        event.Finished(Error(reason), ..), True -> {
          let failed =
            chat.UserMessage("The last reply failed.\n" <> reason, [])
          #([failed, ..history], False)
        }
        _, _ -> acc
      }
    })
  list.reverse(reversed)
}

// The code of a turn from the event that started it.
fn begin(context, state, before, started) -> Result(Segment, String) {
  case started {
    event.Started(code, policy) -> {
      use policy <- result.map(load_policy(state, policy))
      program(policy, code)
    }
    event.Submitted(source, policy) -> {
      use policy <- result.map(load_policy(state, policy))
      built(policy, source)
    }
    event.Sent(message, policy) -> {
      use policy <- result.try(load_policy(state, policy))
      chat(context, state, before, policy, message)
    }
    _ -> Error(mismatch)
  }
}

fn starts(event) {
  case event {
    event.Started(..) | event.Submitted(..) | event.Sent(..) -> True
    _ -> False
  }
}

// The policy a turn was started with.
fn load_policy(state: execute.State, cid) {
  use bytes <- result.try(
    execute.files(mfs.read(cid, []), state)
    |> result.replace_error(Nil)
    |> result.try(result.replace_error(_, Nil))
    |> result.replace_error("the policy " <> v1.to_string(cid) <> " is missing"),
  )
  use code <- result.try(
    bit_array.to_string(bytes)
    |> result.replace_error(
      "the policy " <> v1.to_string(cid) <> " is not text",
    ),
  )
  execute.load_policy(code, state).0
}

// The packages pinned in `state` that were not pinned `before`.
fn pinned(before, state: execute.State) {
  dict.drop(state.pins, dict.keys(before))
  |> dict.to_list
  |> list.filter_map(fn(pin) {
    case pin {
      #(ir.Package(package), module) -> Ok(event.Pinned(package, None, module))
      #(ir.Version(package, version), module) ->
        Ok(event.Pinned(package, Some(version), module))
      _ -> Error(Nil)
    }
  })
}

fn drive(context: Context, session: Session, state, segment: Segment) {
  use start <- result.try(box.latest(context, session.box))
  let start = start.root
  let before = state.pins
  let steered = fn() { live.take(context.live, session.id) }
  let #(stop, answers) = perform(segment(state, start), [], steered)
  let #(last, root, next) = ending(stop, start)
  let events =
    list.flatten([
      [event.Resumed(start)],
      pinned(before, stop.state),
      answers,
      [last],
    ])
  use key <- result.try(record(context, session, events))
  settle(context, session, stop.state, start, root, key, next)
}

// The event that ends a segment, the root of its change and what happens next.
fn ending(stop, start) {
  case stop {
    Stopped(_, outcome, root, output) -> {
      // Code that fails changes nothing.
      let root = case outcome {
        Ok(_) -> root
        Error(_) -> start
      }
      #(
        event.Returned(outcome, output, root),
        root,
        Return(outcome, output, root),
      )
    }
    Leaving(_, wait, left, root, resume) -> #(left, root, Perform(wait, resume))
  }
}

// Merge the change of a segment whose events are recorded, then continue.
// `key` is the key of the segment's last event, it identifies the change so it is only merged once.
fn settle(context: Context, session: Session, state, start, root, key, next) {
  let merged = case root == start {
    True -> Ok(Nil)
    False ->
      box.merge(context, session.box, start, root, Some(key))
      |> result.replace(Nil)
  }
  case merged, next {
    Ok(Nil), Return(outcome, output, root) ->
      finish(context, session, outcome, output, root)
    Ok(Nil), Perform(wait, resume) ->
      answer(context, session, state, wait, resume)
    Ok(Nil), Reply(answer, resume) -> {
      use _ <- result.try(record(context, session, [event.Answered(answer)]))
      drive(context, session, state, continue(resume, answer))
    }
    Error(reason), Return(output:, ..) -> {
      use reason <- result.try(rejected(reason))
      finish(context, session, Error(reason), output, start)
    }
    // The code continues from the latest root, without the rejected changes.
    Error(reason), Perform(_, resume) | Error(reason), Reply(_, resume) -> {
      use reason <- result.try(rejected(reason))
      let answer = execute.Rejected(reason)
      use _ <- result.try(record(context, session, [event.Answered(answer)]))
      drive(context, session, state, continue(resume, answer))
    }
  }
}

// A response is recorded as soon as it is received, sleeping has nothing to record.
fn answer(context: Context, session: Session, state, wait, resume) {
  let answer = case wait {
    // A completion is streamed so its text can be shown as it arrives, only the completion is recorded.
    // If the process stops before then the text is lost and the completion is asked for again.
    execute.Complete(llm, provider, history, _) -> {
      let completed =
        stream.complete(llm, provider, history, live.show(
          context.live,
          session.id,
          _,
        ))
      live.clear(context.live, session.id)
      execute.Completed(completed)
    }
    _ -> execute.perform(wait, state)
  }
  use _ <- result.try(case wait {
    execute.Fetch(_) | execute.Complete(..) ->
      record(context, session, [event.Answered(answer)])
    _ -> Ok("")
  })
  drive(context, session, state, continue(resume, answer))
}

// Answer every effect that does not leave the box process.
// `steered` takes the messages sent to a chat while it ran tool calls.
fn perform(run, answers, steered) {
  case stop(run) {
    Ok(stop) -> #(stop, list.reverse(answers))
    Error(#(wait, state, root, resume)) -> {
      let answer = case wait {
        execute.Steer -> execute.Steered(steered())
        _ -> execute.perform(wait, state)
      }
      let recorded = case wait, answer {
        execute.Env(name), execute.Secret(value) ->
          event.Read(name, fingerprint(name, value))
        _, _ -> event.Answered(answer)
      }
      perform(resume(answer, state, root), [recorded, ..answers], steered)
    }
  }
}

// Enough to notice a secret has changed, a weak secret could be guessed from it.
fn fingerprint(name, value) {
  let value = case value {
    Some(value) -> <<1, value:utf8>>
    None -> <<0>>
  }
  let assert Ok(hash) =
    crypto.hash(crypto.Sha256, <<name:utf8, 0, value:bits>>)
    |> bit_array.slice(0, 8)
  string.lowercase(bit_array.base16_encode(hash))
}

// Code stops when it finishes, makes a request, sleeps or asks for a completion.
fn stop(run) {
  case run {
    execute.Finished(outcome, state, root, output) ->
      Ok(Stopped(state, outcome, root, list.reverse(output)))
    execute.Waiting(execute.Fetch(request) as wait, state, root, resume) ->
      Ok(Leaving(state, wait, event.Requested(request, root), root, resume))
    execute.Waiting(execute.Sleep(milliseconds) as wait, state, root, resume) ->
      Ok(Leaving(state, wait, event.Slept(milliseconds, root), root, resume))
    execute.Waiting(execute.Complete(added:, ..) as wait, state, root, resume) ->
      Ok(Leaving(state, wait, event.Asked(added, root), root, resume))
    execute.Waiting(wait, state, root, resume) ->
      Error(#(wait, state, root, resume))
  }
}

fn finish(context, session, outcome, output, root) {
  let finished = event.Finished(outcome, output, root)
  use _ <- result.map(record(context, session, [finished]))
  #(outcome, output)
}

// A change the box does not accept fails the turn.
fn rejected(reason) {
  case reason {
    box.Invalid(errors) ->
      Ok("File changes rejected\n" <> string.join(errors, "\n"))
    box.Conflict(paths) ->
      Ok("File changes conflict\n" <> string.join(paths, "\n"))
    _ -> Error(reason)
  }
}

// Append events after the session's head and move the head to the last of them, returning its key.
fn record(context: Context, session: Session, events: List(Event)) {
  let failed = fn(reason) { box.Failed(string.inspect(reason)) }
  db.transaction(context.db, fn(connection) {
    let execute = fn(query) {
      db.execute(query, connection) |> result.map_error(failed)
    }
    use found <- result.try(execute(sessions.get(session.id)))
    let assert [session] = found.rows
    let payloads =
      list.map(events, fn(event) { json.to_string(event.encode(event)) })
    let nodes = thread.nodes(session.head, payloads)
    let assert Ok(last) = list.last(nodes)
    use _ <- result.try(
      db.execute(thread.insert(nodes), connection) |> result.map_error(failed),
    )
    let move = sessions.move(session.id, session.head, last.key)
    use moved <- result.try(execute(move))
    case moved.rows {
      [_] -> Ok(last.key)
      // Only the session's process moves its head, this is a safety check.
      _ -> Error(box.Failed("the session was moved by another process"))
    }
  })
  |> result.map_error(fn(error) {
    case error {
      pog.TransactionRolledBack(reason) -> reason
      pog.TransactionQueryError(reason) -> failed(reason)
    }
  })
}

/// Every event in the session's history, with the time it was recorded in microseconds and its key.
pub fn history(
  context: Context,
  session: String,
) -> Result(List(#(Int, String, Event)), box.Reason) {
  let failed = fn(reason) { box.Failed(string.inspect(reason)) }
  use found <- result.try(
    db.execute(sessions.get(session), context.db) |> result.map_error(failed),
  )
  case found.rows {
    [sessions.Session(head: Some(head), ..)] -> {
      use returned <- result.try(
        db.execute(thread.history(head), context.db) |> result.map_error(failed),
      )
      list.try_map(returned.rows, fn(entry) {
        let #(at, thread.Node(key:, payload:, ..)) = entry
        json.parse(payload, event.decoder())
        |> result.map(fn(event) { #(at, key, event) })
        |> result.map_error(fn(reason) { box.Failed(string.inspect(reason)) })
      })
    }
    [_] -> Ok([])
    _ -> Error(box.Missing)
  }
}

// Finish the last turn if the process running it stopped.
fn recover(context: Context, session: Session) -> Result(Nil, box.Reason) {
  use history <- result.try(history(context, session.id))
  let entries = list.map(history, fn(entry) { #(entry.1, entry.2) })
  case unfinished(entries) {
    Error(Nil) -> Ok(Nil)
    Ok(#(before, started, entries)) -> {
      let #(state, entries) = pins(context.state, entries)
      let position = {
        use segment <- result.try(begin(context, state, before, started))
        walk(state, segment, entries)
      }
      case position {
        Ok(Stalled(segment, state)) -> drive(context, session, state, segment)
        // A request that might have been received is not sent again.
        Ok(Unsettled(
          start,
          root,
          key,
          Perform(execute.Fetch(request), resume),
          state,
        ))
          if request.method != http.Get && request.method != http.Head
        -> {
          let answer =
            execute.Fetched(Error(
              "network error, the session stopped before the response was recorded",
            ))
          let next = Reply(answer, resume)
          settle(context, session, state, start, root, key, next)
        }
        // A sleep that was stopped is started again, a completion is asked for again.
        Ok(Unsettled(start, root, key, next, state)) ->
          settle(context, session, state, start, root, key, next)
        Ok(Ended(_)) -> Error(box.Failed(mismatch))
        Error(reason) -> Error(box.Failed(reason))
      }
      |> result.replace(Nil)
    }
  }
}

// The events before the last turn, the event that started it and its events, if it has no finished event.
fn unfinished(entries: List(#(String, Event))) {
  let last =
    list.index_fold(entries, Error(Nil), fn(last, entry, i) {
      case entry.1 {
        event.Finished(..) -> Error(Nil)
        event ->
          case starts(event) {
            True -> Ok(i)
            False -> last
          }
      }
    })
  use i <- result.try(last)
  case list.split(entries, i) {
    #(before, [#(_, started), ..entries]) -> Ok(#(before, started, entries))
    _ -> Error(Nil)
  }
}

// A package resolves to the same module throughout a turn, so the pins from all of a turn's events
// are set before it is replayed. They are left out of the events to replay.
fn pins(state: execute.State, entries: List(#(String, Event))) {
  let #(pins, entries) =
    list.partition(entries, fn(entry) {
      case entry.1 {
        event.Pinned(..) -> True
        _ -> False
      }
    })
  let pins =
    list.fold(pins, dict.new(), fn(pins, entry) {
      case entry.1 {
        event.Pinned(package, None, module) ->
          dict.insert(pins, ir.Package(package), module)
        event.Pinned(package, Some(version), module) ->
          dict.insert(pins, ir.Version(package, version), module)
        _ -> pins
      }
    })
  #(execute.State(..state, pins:), entries)
}

// Code in a box reads the secrets of the box.
fn in_box(context: Context, box) {
  use secrets <- result.map(box.secrets(context, box))
  Context(..context, state: execute.State(..context.state, secrets:))
}

/// Replay every turn, as if it ran in the box, and check it does what the events say it did.
/// The blocks of every root in the events must be in the blob store.
pub fn check(
  context: Context,
  box: String,
  events: List(Event),
) -> Result(Nil, String) {
  use context <- result.try(
    in_box(context, box) |> result.replace_error("the box is unavailable"),
  )
  case list.map(events, fn(event) { #("", event) }) {
    [#(_, event.Configured(_)) as configured, ..entries] ->
      do_check(context, [configured], entries)
    entries -> do_check(context, [], entries)
  }
}

fn do_check(context: Context, before, entries) {
  case entries {
    [] -> Ok(Nil)
    [#(_, started) as first, ..entries] -> {
      let #(turn, rest) =
        list.split_while(entries, fn(entry) { !starts(entry.1) })
      let #(state, replayed) = pins(context.state, turn)
      use segment <- result.try(begin(context, state, before, started))
      case walk(state, segment, replayed), rest {
        Ok(Ended([])), _ ->
          do_check(context, list.flatten([before, [first], turn]), rest)
        // Only the last turn can be unfinished.
        Ok(Stalled(..)), [] | Ok(Unsettled(..)), [] -> Ok(Nil)
        Ok(_), _ -> Error(mismatch)
        Error(reason), _ -> Error(reason)
      }
    }
  }
}

// How far the events of a turn go.
type Position {
  Ended(rest: List(#(String, Event)))
  // The next segment's events were never recorded.
  Stalled(Segment, execute.State)
  // The last segment's events are recorded, its change might not be merged and nothing after it happened.
  Unsettled(
    start: v1.Cid,
    root: v1.Cid,
    key: String,
    next: Next,
    state: execute.State,
  )
}

/// Run the code again with the answers that were recorded.
fn walk(state, segment: Segment, entries) {
  case entries {
    [] -> Ok(Stalled(segment, state))
    // The turn was cancelled.
    [#(_, event.Finished(..)), ..entries] -> Ok(Ended(entries))
    [#(_, event.Resumed(start)), ..entries] -> {
      use #(stop, entries) <- result.try(replay_answers(
        segment(state, start),
        entries,
      ))
      let #(last, root, next) = ending(stop, start)
      let state = stop.state
      case entries {
        [#(key, recorded), ..entries] if recorded == last ->
          case next, entries {
            _, [] -> Ok(Unsettled(start, root, key, next, state))
            // The turn finished, or its last change was rejected.
            _, [#(_, event.Finished(..)), ..entries] -> Ok(Ended(entries))
            Perform(_, resume),
              [#(_, event.Answered(execute.Rejected(_) as answer)), ..entries]
            -> walk(state, continue(resume, answer), entries)
            Perform(execute.Fetch(_), resume),
              [#(_, event.Answered(answer)), ..entries]
            | Perform(execute.Complete(..), resume),
              [#(_, event.Answered(answer)), ..entries]
            -> walk(state, continue(resume, answer), entries)
            Perform(execute.Sleep(_), resume), _ ->
              walk(state, continue(resume, execute.Slept), entries)
            _, _ -> Error(mismatch)
          }
        _ -> Error(mismatch)
      }
    }
    _ -> Error(mismatch)
  }
}

fn continue(resume: Resume, answer) -> Segment {
  fn(state, root) { resume(answer, state, root) }
}

fn replay_answers(run, entries) {
  case stop(run), entries {
    Ok(stop), _ -> Ok(#(stop, entries))
    // The secret is read again, it must be the one that was read before.
    Error(#(execute.Env(name), state, root, resume)),
      [#(_, event.Read(recorded, fingerprint_)), ..entries]
      if name == recorded
    -> {
      let value = dict.get(state.secrets, name) |> option.from_result
      case fingerprint(name, value) == fingerprint_ {
        True ->
          resume(execute.Secret(value), state, root)
          |> replay_answers(entries)
        False ->
          Error("the secret " <> name <> " has changed since the turn ran")
      }
    }
    Error(#(_, state, root, resume)), [#(_, event.Answered(answer)), ..entries]
    -> replay_answers(resume(answer, state, root), entries)
    Error(_), _ -> Error(mismatch)
  }
}

const mismatch = "the session events do not match the code"
