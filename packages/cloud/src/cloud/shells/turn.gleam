//// Run code in a shell so that it can be resumed from the shell's journal.
////
//// Code runs in segments, in the shell's process, until it finishes, makes a request or sleeps.
//// Before a segment runs its input is appended to the journal, with the box event the segment starts from.
//// When it stops its output is appended, in the same transaction as the box event of the files it changed,
//// so the journal and the box never disagree. A segment that only read files never waits for the box process.
//// A change that conflicts or does not type check is rejected and the request is not made.
//// The code continues from the box's latest root with the rejection as its answer, and fails with it.
//// The response to a request is appended as the input of the next segment as soon as it is received.
////
//// If the process stops, the code is replayed with the recorded answers the next time the shell is used.
//// A segment whose output was not recorded runs again from its input.
//// A request whose response was not recorded is sent again if it is GET or HEAD,
//// any other request is answered with a network error as it might have been received.
////
//// A shell made for a tool call or for code sent to a chat runs that code as its only turn, see `once`.
////
//// Each turn records the policy it runs with and the module each package reference resolved to,
//// so a replay runs the same code after the policy changes or a package is released.
//// Code reads the secrets of its box. Secrets are never recorded, a fingerprint of each secret read is recorded instead.
//// If a secret changed the turn cannot be replayed and fails saying which secret changed.

import cloud/apex/context.{type Context, Context}
import cloud/beam/execute
import cloud/box
import cloud/data/boxes.{type Box}
import cloud/data/db
import cloud/data/journal
import cloud/data/shells.{type Shell}
import cloud/registry
import cloud/shells/event.{type Entry}
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/erlang/process
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import pog
import touch_grass/source
import unixfs/mfs

/// What a turn came to and everything it printed.
pub type Outcome =
  #(Result(String, String), List(String))

type Segment =
  fn(execute.State, v1.Cid) -> execute.Run(String)

type Resume =
  fn(execute.Answer, execute.State, v1.Cid) -> execute.Run(String)

// What happens after a segment's output is recorded.
type Next {
  Return(outcome: Result(String, String), output: List(String))
  Perform(execute.Wait, Resume)
}

// Where a segment of code stops.
type Stop {
  Stopped(
    state: execute.State,
    outcome: Result(String, String),
    root: v1.Cid,
    output: List(String),
  )
  // A request or sleep is done outside the box process, `stop` is how it is recorded.
  Leaving(
    state: execute.State,
    wait: execute.Wait,
    stop: event.Stop,
    root: v1.Cid,
    resume: Resume,
  )
}

// A shell's journal as it is written, `next` is the sequence of its next entry.
type Writer {
  Writer(shell: Shell, next: Int)
}

/// What is sent to a shell.
pub type Input {
  Code(String)
  /// A program built in a structural editor.
  Program(ir.Node(Nil))
}

/// A new shell in the box, for a person or a cron.
pub fn start(context: Context, box: String) -> Result(Shell, box.Reason) {
  create(context, box, shells.Anyone)
}

/// A new shell in the box, `for` is what it runs code for.
pub fn create(
  context: Context,
  box: String,
  for: shells.For,
) -> Result(Shell, box.Reason) {
  use _ <- result.try(box.latest(context, box))
  case query(context, shells.create(box, for)) {
    Ok([shell]) -> Ok(shell)
    Ok(_) -> Error(box.Failed("the shell could not be made"))
    Error(reason) -> Error(reason)
  }
}

pub fn find(context: Context, id: String) -> Result(Shell, box.Reason) {
  case query(context, shells.get(id)) {
    Ok([shell]) -> Ok(shell)
    Ok(_) -> Error(box.Missing)
    Error(reason) -> Error(reason)
  }
}

/// A new shell in the same box with a copy of the shell's journal.
pub fn fork(context: Context, id: String) -> Result(Shell, box.Reason) {
  use shell <- result.try(find(context, id))
  transaction(context, fn(context) {
    use forked <- result.try(
      case query(context, shells.create(shell.box, shells.Anyone)) {
        Ok([forked]) -> Ok(forked)
        Ok(_) -> Error(box.Failed("the shell could not be forked"))
        Error(reason) -> Error(reason)
      },
    )
    use _ <- result.map(query(context, journal.copy(id, forked.id)))
    forked
  })
}

/// The most recent shells in any box, with the name of the box if it has one.
/// Shells in transient boxes are left out unless `transient` is true.
pub fn recent(
  context: Context,
  limit: Int,
  transient: Bool,
) -> Result(List(shells.Listed), box.Reason) {
  query(context, shells.recent(limit, transient))
}

/// Whether the last turn in the entries has not finished.
pub fn unfinished_turn(entries: List(Entry)) -> Bool {
  unfinished(entries) |> result.is_ok
}

/// Run a turn in the shell's process, which runs one turn at a time.
pub fn send(
  context: Context,
  shell: Shell,
  input: Input,
) -> Result(Outcome, box.Reason) {
  in_process(context, shell, fn() { run(context, shell, input) })
}

/// Run the code as the only turn of a shell made for it, such as for a tool call.
/// A turn that already started is finished rather than started again, so the code runs once
/// however many times this is called, and each call has what it came to.
pub fn once(
  context: Context,
  shell: Shell,
  code: String,
) -> Result(Outcome, box.Reason) {
  use <- in_process(context, shell)
  use recorded <- result.try(entries(context, shell.id))
  case recorded {
    [] -> run(context, shell, Code(code))
    _ -> {
      use context <- result.try(in_box(context, shell.box))
      use Nil <- result.try(recover(context, shell))
      use recorded <- result.try(entries(context, shell.id))
      Ok(ended(recorded))
    }
  }
}

// What the last turn in the entries came to, it has finished or was cancelled.
fn ended(entries: List(Entry)) -> Outcome {
  list.fold(entries, #(Error("the turn did not finish"), []), fn(ended, entry) {
    case entry {
      event.Output(stop: event.Finished(_, output) as stop, change:, ..) -> #(
        outcome(stop, change),
        output,
      )
      event.Input(event.Cancelled, ..) -> #(Error("cancelled"), [])
      _ -> ended
    }
  })
}

/// Finish the last turn if it is unfinished, after a turn that is running finishes.
pub fn resume(context: Context, shell: Shell) -> Result(Nil, box.Reason) {
  use <- in_process(context, shell)
  use context <- result.try(in_box(context, shell.box))
  recover(context, shell)
}

fn in_process(context: Context, shell: Shell, then) {
  registry.lookup(context.shells, shell.id, fn() { registry.serve(Nil) })
  |> registry.call(600_000, fn(_) { #(Nil, then()) })
}

/// Stop a turn that is running and record that it was cancelled, so it is not resumed.
/// Changes that were merged are kept, a change that was waiting to be merged is not merged.
pub fn cancel(context: Context, shell: Shell) -> Result(Nil, box.Reason) {
  let process =
    registry.lookup(context.shells, shell.id, fn() { registry.serve(Nil) })
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
  use entries <- result.try(entries(context, shell.id))
  case unfinished(entries) {
    Error(Nil) -> Ok(Nil)
    Ok(_) -> {
      use box <- result.try(box.latest(context, shell.box))
      writer(shell, entries)
      |> append(context, _, [
        event.Input(event.Cancelled, box.sequence, box.root),
      ])
      |> result.replace(Nil)
    }
  }
}

/// Run a turn in the shell, an unfinished turn is finished first.
pub fn run(
  context: Context,
  shell: Shell,
  input: Input,
) -> Result(Outcome, box.Reason) {
  use context <- result.try(in_box(context, shell.box))
  use Nil <- result.try(recover(context, shell))
  use before <- result.try(entries(context, shell.id))
  let state = execute.State(..context.state, pins: dict.new())
  let #(policy, state) =
    execute.load_policy(
      context.policy,
      source.Inline,
      state,
      execute.template(),
    )
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
  use #(trigger, segment) <- result.try(case input {
    Code(code) -> Ok(#(event.Started(code, stored), program(policy, code)))
    Program(source) ->
      Ok(#(event.Submitted(source, stored), built(policy, source)))
  })
  use box <- result.try(box.latest(context, shell.box))
  let input = event.Input(trigger, box.sequence, box.root)
  use writer <- result.try(append(context, writer(shell, before), [input]))
  // Packages pinned while loading the policy are recorded with the first segment.
  drive(context, writer, state, segment, box.root, dict.new())
}

fn program(policy, code) -> Segment {
  fn(state, root) { execute.run(code, state, policy, root, fn(_) { Nil }) }
}

fn built(policy, source) -> Segment {
  fn(state, root) {
    execute.program(source, state, policy, root, fn(_) { Nil })
  }
}

/// What a turn that finished came to, a change that was rejected fails the turn.
pub fn outcome(
  stop: event.Stop,
  change: event.Change,
) -> Result(String, String) {
  case stop, change {
    event.Finished(_, _), event.Rejected(reason) -> Error(reason)
    event.Finished(outcome, _), _ -> outcome
    _, _ -> Error("the turn did not finish")
  }
}

// The code of a turn from the trigger that started it.
fn begin(state, trigger) -> Result(Segment, String) {
  case trigger {
    event.Started(code, policy) -> {
      use policy <- result.map(load_policy(state, policy))
      program(policy, code)
    }
    event.Submitted(source, policy) -> {
      use policy <- result.map(load_policy(state, policy))
      built(policy, source)
    }
    _ -> Error(mismatch)
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
  execute.load_policy(code, source.Inline, state, execute.template()).0
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

// Run a segment from `start`, whose input is recorded, then record its output and continue.
fn drive(context: Context, writer, state, segment: Segment, start, before) {
  let #(stop, answers) = perform(segment(state, start), [])
  let answers = list.append(pinned(before, stop.state), answers)
  let #(recorded, root, next) = ending(stop, start)
  let output = event.Output(answers, recorded, root, _)
  settle(context, writer, stop.state, start, root, output, next)
}

// How a stop is recorded, the root of the change the segment made and what happens next.
fn ending(stop, start) {
  case stop {
    Stopped(_, outcome, root, output) -> {
      // Code that fails changes nothing.
      let root = case outcome {
        Ok(_) -> root
        Error(_) -> start
      }
      #(event.Finished(outcome, output), root, Return(outcome, output))
    }
    Leaving(_, wait, stop, root, resume) -> #(stop, root, Perform(wait, resume))
  }
}

// Record the output of a segment with its change, then continue.
// A change is merged into the box in the same transaction as the output is recorded.
fn settle(
  context: Context,
  writer: Writer,
  state: execute.State,
  start,
  root,
  output,
  next,
) {
  case root == start {
    True -> {
      use writer <- result.try(
        append(context, writer, [output(event.Unchanged)]),
      )
      proceed(context, writer, state, next)
    }
    False -> {
      let merged =
        box.merge_with(context, writer.shell.box, start, root, fn(merged) {
          case merged {
            box.Accepted(_) -> rows(writer, [output(event.Merged)])
            box.Refused(reason, current) ->
              case rejected(reason) {
                Ok(reason) ->
                  rows(writer, refused(output, reason, next, current))
                Error(_) -> []
              }
          }
        })
      case merged {
        Ok(box.Accepted(_)) -> proceed(context, advance(writer, 1), state, next)
        Ok(box.Refused(reason, current)) -> {
          use reason <- result.try(rejected(reason))
          case next {
            Return(output:, ..) -> Ok(#(Error(reason), output))
            // The code continues from the box that refused the change, without it.
            Perform(_, resume) ->
              drive(
                context,
                advance(writer, 2),
                state,
                continue(resume, execute.Rejected(reason)),
                current.root,
                state.pins,
              )
          }
        }
        Error(reason) -> Error(reason)
      }
    }
  }
}

// The entries recorded when the box refuses a change, code that is waiting continues with the rejection.
fn refused(output, reason, next, current: Box) {
  case next {
    Return(..) -> [output(event.Rejected(reason))]
    Perform(..) -> [
      output(event.Rejected(reason)),
      event.Input(
        event.Continued(execute.Rejected(reason)),
        current.sequence,
        current.root,
      ),
    ]
  }
}

// After a segment's output is recorded, finish or wait for the answer the code stopped for.
fn proceed(context: Context, writer, state, next) {
  case next {
    Return(outcome, output) -> Ok(#(outcome, output))
    Perform(wait, resume) -> answer(context, writer, state, wait, resume)
  }
}

// A response is recorded as soon as it is received, as the input of the next segment.
fn answer(context: Context, writer: Writer, state, wait, resume) {
  let answer = execute.perform(wait, state)
  continue_with(context, writer, state, resume, answer)
}

// Record the answer as the input of the next segment, then run it from the box's latest root.
fn continue_with(
  context: Context,
  writer: Writer,
  state: execute.State,
  resume,
  answer,
) {
  use current <- result.try(box.latest(context, writer.shell.box))
  let input =
    event.Input(event.Continued(answer), current.sequence, current.root)
  use writer <- result.try(append(context, writer, [input]))
  drive(
    context,
    writer,
    state,
    continue(resume, answer),
    current.root,
    state.pins,
  )
}

// Answer every effect that does not leave the box process.
fn perform(run, answers) {
  case stop(run) {
    Ok(stop) -> #(stop, list.reverse(answers))
    Error(#(wait, state, root, resume)) -> {
      let answer = execute.perform(wait, state)
      let recorded = case wait, answer {
        execute.Env(name), execute.Secret(value) ->
          event.Read(name, fingerprint(name, value))
        _, _ -> event.Answered(answer)
      }
      perform(resume(answer, state, root), [recorded, ..answers])
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

// Code stops when it finishes, makes a request or sleeps.
fn stop(run) {
  case run {
    execute.Finished(outcome, state, root, output) ->
      Ok(Stopped(state, outcome, root, list.reverse(output)))
    execute.Waiting(execute.Fetch(request) as wait, state, root, resume) ->
      Ok(Leaving(state, wait, event.Requested(request), root, resume))
    execute.Waiting(execute.Sleep(milliseconds) as wait, state, root, resume) ->
      Ok(Leaving(state, wait, event.Slept(milliseconds), root, resume))
    execute.Waiting(wait, state, root, resume) ->
      Error(#(wait, state, root, resume))
  }
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

fn writer(shell: Shell, entries: List(Entry)) -> Writer {
  Writer(shell, list.length(entries) + 1)
}

fn advance(writer: Writer, by: Int) -> Writer {
  Writer(..writer, next: writer.next + by)
}

// The queries that append the entries after the ones already written.
fn rows(writer: Writer, entries: List(Entry)) -> List(pog.Query(Nil)) {
  list.index_map(entries, fn(entry, i) {
    let start = case entry {
      event.Input(start:, ..) -> Some(start)
      event.Output(..) -> None
    }
    journal.Row(writer.next + i, start, event.stored(entry))
    |> journal.append(writer.shell.id, writer.shell.box, _)
  })
}

// Append entries to the journal. It fails if another process appended first.
fn append(context: Context, writer: Writer, entries: List(Entry)) {
  use Nil <- result.map(
    transaction(context, fn(context) {
      list.try_each(rows(writer, entries), fn(row) {
        query(context, row) |> result.replace(Nil)
      })
    }),
  )
  advance(writer, list.length(entries))
}

/// Every entry in the shell's journal, with the time it was recorded in microseconds.
pub fn history(
  context: Context,
  shell: String,
) -> Result(List(#(Int, Entry)), box.Reason) {
  use _ <- result.try(find(context, shell))
  use recorded <- result.try(query(context, journal.entries(shell)))
  list.try_map(recorded, fn(recorded) {
    json.parse(recorded.entry, event.decoder(recorded.start))
    |> result.map(fn(entry) { #(recorded.at, entry) })
    |> result.map_error(fn(reason) { box.Failed(string.inspect(reason)) })
  })
}

fn entries(context, shell) {
  history(context, shell)
  |> result.map(list.map(_, fn(entry) { entry.1 }))
}

// How far the entries of a turn go.
type Position {
  Ended
  // The segment's input is recorded, its output was not.
  Stalled(Segment, execute.State, v1.Cid)
  // The segment stopped to wait, the answer was not recorded.
  Unanswered(execute.Wait, Resume, execute.State)
}

// Finish the last turn if the process running it stopped.
fn recover(context: Context, shell: Shell) -> Result(Nil, box.Reason) {
  use entries <- result.try(entries(context, shell.id))
  case unfinished(entries) {
    Error(Nil) -> Ok(Nil)
    Ok(#(_, turn)) -> {
      let writer = writer(shell, entries)
      let state = pins(context.state, turn)
      let position = case turn {
        [event.Input(trigger, ..), ..] -> {
          use segment <- result.try(begin(state, trigger))
          walk(state, segment, turn)
        }
        _ -> Error(mismatch)
      }
      case position {
        Ok(Stalled(segment, state, start)) ->
          drive(context, writer, state, segment, start, state.pins)
        // A request that might have been received is not sent again.
        Ok(Unanswered(execute.Fetch(request), resume, state))
          if request.method != http.Get && request.method != http.Head
        -> {
          let answer =
            execute.Fetched(Error(
              "network error, the shell stopped before the response was recorded",
            ))
          continue_with(context, writer, state, resume, answer)
        }
        // A sleep that was stopped is started again.
        Ok(Unanswered(wait, resume, state)) ->
          answer(context, writer, state, wait, resume)
        Ok(Ended) -> Error(box.Failed(mismatch))
        Error(reason) -> Error(box.Failed(reason))
      }
      |> result.replace(Nil)
    }
  }
}

// The entries before the last turn and the entries of the turn, if it has not finished.
fn unfinished(entries: List(Entry)) {
  let last =
    list.index_fold(entries, Error(Nil), fn(last, entry, i) {
      case entry {
        event.Input(trigger, ..) ->
          case event.starts(trigger) {
            True -> Ok(i)
            False -> last
          }
        _ -> last
      }
    })
  use i <- result.try(last)
  let #(before, turn) = list.split(entries, i)
  let ended =
    list.any(turn, fn(entry) {
      case entry {
        event.Output(stop: event.Finished(..), ..) -> True
        event.Input(event.Cancelled, ..) -> True
        _ -> False
      }
    })
  case ended {
    True -> Error(Nil)
    False -> Ok(#(before, turn))
  }
}

// A package resolves to the same module throughout a turn, so the pins from all of a turn's outputs
// are set before it is replayed.
fn pins(state: execute.State, turn: List(Entry)) {
  let pins =
    list.fold(turn, dict.new(), fn(pins, entry) {
      case entry {
        event.Output(answers:, ..) ->
          list.fold(answers, pins, fn(pins, answer) {
            case answer {
              event.Pinned(package, None, module) ->
                dict.insert(pins, ir.Package(package), module)
              event.Pinned(package, Some(version), module) ->
                dict.insert(pins, ir.Version(package, version), module)
              _ -> pins
            }
          })
        _ -> pins
      }
    })
  execute.State(..state, pins:)
}

// Code in a box reads the secrets of the box.
fn in_box(context: Context, box) {
  use secrets <- result.map(box.secrets(context, box))
  Context(..context, state: execute.State(..context.state, secrets:))
}

/// Run the code again with the answers that were recorded, from the input that starts the turn.
fn walk(state, segment: Segment, entries) {
  case entries {
    [event.Input(root: start, ..), ..entries] ->
      case entries {
        [] -> Ok(Stalled(segment, state, start))
        [event.Output(answers, recorded, root, change), ..entries] -> {
          let answers =
            list.filter(answers, fn(answer) {
              case answer {
                event.Pinned(..) -> False
                _ -> True
              }
            })
          use stop <- result.try(replay_answers(segment(state, start), answers))
          let #(stopped, changed, next) = ending(stop, start)
          let state = stop.state
          case stopped == recorded && changed == root, next, change, entries {
            False, _, _, _ -> Error(mismatch)
            True, Return(..), _, _ -> Ok(Ended)
            True, Perform(wait, resume), _, [] ->
              case change {
                // The rejection is recorded with the output, as the next input.
                event.Rejected(_) -> Error(mismatch)
                _ -> Ok(Unanswered(wait, resume, state))
              }
            True, Perform(_, _), _, [event.Input(event.Cancelled, ..), ..] ->
              Ok(Ended)
            True,
              Perform(_, resume),
              _,
              [event.Input(event.Continued(answer), ..), ..] as entries
            -> walk(state, continue(resume, answer), entries)
            True, _, _, _ -> Error(mismatch)
          }
        }
        _ -> Error(mismatch)
      }
    _ -> Error(mismatch)
  }
}

fn continue(resume: Resume, answer) -> Segment {
  fn(state, root) { resume(answer, state, root) }
}

fn replay_answers(run, answers) {
  case stop(run), answers {
    Ok(stop), [] -> Ok(stop)
    // The secret is read again, it must be the one that was read before.
    Error(#(execute.Env(name), state, root, resume)),
      [event.Read(recorded, fingerprint_), ..answers]
      if name == recorded
    -> {
      let value = dict.get(state.secrets, name) |> option.from_result
      case fingerprint(name, value) == fingerprint_ {
        True ->
          resume(execute.Secret(value), state, root)
          |> replay_answers(answers)
        False ->
          Error("the secret " <> name <> " has changed since the turn ran")
      }
    }
    Error(#(_, state, root, resume)), [event.Answered(answer), ..answers] ->
      replay_answers(resume(answer, state, root), answers)
    _, _ -> Error(mismatch)
  }
}

const mismatch = "the shell journal does not match the code"

fn query(context: Context, query) {
  db.execute(query, context.db)
  |> result.map(fn(returned: pog.Returned(_)) { returned.rows })
  |> result.map_error(fn(reason) { box.Failed(string.inspect(reason)) })
}

fn transaction(context: Context, then) {
  db.transaction(context.db, fn(connection) {
    then(Context(..context, db: connection))
  })
  |> result.map_error(fn(error) {
    case error {
      pog.TransactionRolledBack(reason) -> reason
      pog.TransactionQueryError(reason) -> box.Failed(string.inspect(reason))
    }
  })
}
