//// A session can be resumed from any point it might stop.
////
//// Events are committed in groups, so a stopped session leaves its events at the end of a group.
//// For random programs every such point is tried: a copy of the session is made from the events
//// up to that point and resumed, sometimes after another change to the box.

import cloud/beam/execute
import cloud/box
import cloud/data/boxes
import cloud/file_system
import cloud/helpers
import cloud/server.{type Server}
import cloud/session_helpers
import cloud/sessions/event
import cloud/sessions/turn
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/list
import gleam/string
import qcheck

type Step {
  Write(Int)
  Read(Int)
  Random
  Flip
  Now
  Sleep
  Get
  Post
  // Writing a module that does not parse is rejected when the changes are committed.
  Invalid
}

fn step() {
  qcheck.from_generators(qcheck.map(qcheck.bounded_int(0, 2), Write), [
    qcheck.map(qcheck.bounded_int(0, 2), Read),
    qcheck.constant(Random),
    qcheck.constant(Flip),
    qcheck.constant(Now),
    qcheck.constant(Sleep),
    qcheck.constant(Get),
    qcheck.constant(Get),
    qcheck.constant(Post),
    qcheck.constant(Invalid),
  ])
}

fn code(steps, server, id) {
  let lines =
    list.index_map(steps, fn(step, i) {
      "let s"
      <> int.to_string(i)
      <> " = "
      <> expression(step, server, path(id, i))
    })
  let fields =
    list.index_map(steps, fn(_, i) {
      let name = "s" <> int.to_string(i)
      name <> ": " <> name
    })
  string.join(lines, "\n") <> "\n{" <> string.join(fields, ", ") <> "}"
}

fn path(id, i) {
  "/" <> id <> "/" <> int.to_string(i)
}

fn expression(step, server, path) {
  case step {
    Write(file) ->
      "perform WriteFile({path: \"/"
      <> int.to_string(file)
      <> ".txt\", contents: !string_to_binary(\"x\")})"
    Read(file) ->
      "perform ReadFile({path: \"/"
      <> int.to_string(file)
      <> ".txt\", offset: 0, limit: 10})"
    Random -> "perform Random(1000)"
    Flip -> "perform Flip({})"
    Now -> "perform Now({})"
    Sleep -> "perform Sleep(0)"
    Get -> server.fetch(server, "GET", path)
    Post -> server.fetch(server, "POST", path)
    Invalid ->
      "perform WriteFile({path: \"/bad.eyg\", contents: !string_to_binary(\"let x =\")})"
  }
}

pub fn resume_from_any_stop_test() {
  let server = server.start(process.new_subject())
  let config = qcheck.default_config() |> qcheck.with_test_count(25)
  use steps <- qcheck.run(
    config,
    qcheck.generic_list(step(), qcheck.bounded_int(1, 6)),
  )
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let id = int.to_string(int.random(1_000_000_000))
  let assert Ok(_) =
    session_helpers.run(context, session, code(steps, server, id))
  let log = session_helpers.export(context, session)
  let lines = string.split(log, "\n") |> list.filter(fn(line) { line != "" })
  let events = session_helpers.events(context, session)
  let assert Ok(Nil) = turn.check(context, events)

  list.index_map(events, fn(event, i) { #(event, i + 1) })
  |> list.filter(fn(entry) { ends_group(entry.0) })
  |> list.each(fn(entry) {
    let #(_, length) = entry
    let prefix = list.take(events, length)
    use root, k <- list.index_map(box_roots(events, length))
    // The copy works on its own box, with the files the box had at the stop.
    let name = "copy-" <> int.to_string(length) <> "-" <> int.to_string(k)
    let assert Ok(_) = box.clone(context, boxes.Box("home", 0, root), name)
    let log = string.join(list.take(lines, length), "\n")
    let assert Ok(copy) = session_helpers.import_(context, name, log)
    // Another process changes the box before the session is resumed.
    case length % 2 {
      0 -> {
        let assert Ok(_) =
          box.change(context, name, fn(root) {
            file_system.write(root, "/other.txt", <<int.to_string(length):utf8>>)
          })
        Nil
      }
      _ -> Nil
    }
    let before = counts(server, steps, id)
    let assert Ok(#(Ok("{}"), [])) = session_helpers.run(context, copy, "{}")
    let after = counts(server, steps, id)

    let copied = session_helpers.events(context, copy)
    let assert Ok(Nil) = turn.check(context, copied)
    let assert [_, ..] = list.filter(copied, is_finished)
    assert list.take(copied, length) == prefix

    list.zip(steps, list.zip(before, after))
    |> list.index_map(fn(step_counts, i) {
      let #(step, #(before, after)) = step_counts
      let sent = after - before
      let expected = case requested(events, length, path(id, i)), step {
        // A response that was recorded is replayed.
        Answered, _ -> [0]
        // A request is not made if the changes before it are rejected.
        Pending(rejected: True), _ -> [0]
        Pending(rejected: False), Get -> [1]
        Pending(rejected: False), _ -> [0]
        NotRequested, _ -> [0, 1]
      }
      assert list.contains(expected, sent)
    })
    Nil
  })
}

// The roots the box can have when a session stops after `length` events.
// Between recording a segment's events and merging its change the box has either root.
fn box_roots(events, length) {
  let prefix = list.take(events, length)
  let ended =
    list.index_map(prefix, fn(event, i) { #(event, i) })
    |> list.filter(fn(entry) {
      case entry.0 {
        event.Requested(..) | event.Slept(..) | event.Returned(..) -> True
        _ -> False
      }
    })
    |> list.last
  case ended {
    Error(Nil) -> [first_root(events)]
    Ok(#(_, i)) -> {
      let base = last_resumed(list.take(prefix, i))
      // Nothing else changes the box, so the merged root is where the code continued from.
      let merged = first_root(list.drop(events, i + 1))
      case i + 1 == length {
        True -> list.unique([base, merged])
        False -> [merged]
      }
    }
  }
}

fn first_root(events) {
  let assert Ok(root) =
    list.find_map(events, fn(event) {
      case event {
        event.Resumed(root) | event.Finished(root:, ..) -> Ok(root)
        _ -> Error(Nil)
      }
    })
  root
}

fn last_resumed(events) {
  let assert Ok(root) =
    list.reverse(events)
    |> list.find_map(fn(event) {
      case event {
        event.Resumed(root) -> Ok(root)
        _ -> Error(Nil)
      }
    })
  root
}

fn ends_group(event) {
  case event {
    event.Started(..)
    | event.Requested(..)
    | event.Slept(..)
    | event.Returned(..)
    | event.Answered(execute.Fetched(_))
    | event.Finished(..) -> True
    _ -> False
  }
}

fn is_finished(event) {
  case event {
    event.Finished(..) -> True
    _ -> False
  }
}

type Requested {
  Answered
  // The prefix ends with the request, `rejected` if the changes before it were.
  Pending(rejected: Bool)
  NotRequested
}

fn requested(events, length, path) {
  case
    list.drop_while(
      list.index_map(events, fn(event, i) { #(event, i) }),
      fn(entry) {
        case entry.0 {
          event.Requested(request, _) -> request.path != path
          _ -> True
        }
      },
    )
  {
    [#(_, i), ..rest] if i < length ->
      case i + 1 == length, rest {
        False, _ -> Answered
        True, [#(event.Finished(..), _), ..] -> Pending(rejected: True)
        True, _ -> Pending(rejected: False)
      }
    _ -> NotRequested
  }
}

fn counts(server: Server, steps, id) {
  list.index_map(steps, fn(step, i) {
    let method = case step {
      Post -> http.Post
      _ -> http.Get
    }
    server.count_requests(server, method, path(id, i))
  })
}
