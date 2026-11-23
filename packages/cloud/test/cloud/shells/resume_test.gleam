//// A shell can be resumed from any point it might stop.
////
//// Entries are appended in transactions, so a stopped shell leaves its journal at the end of one.
//// For random programs every such point is tried: a shell in the same box is made with the entries
//// up to that point and resumed, sometimes after another change to the box.
//// A program is run as code, as a program built in an editor, or as a chat where the llm makes a tool call for each step.

import cloud/box
import cloud/file_system
import cloud/helpers
import cloud/server.{type Server}
import cloud/shell_helpers
import cloud/shells/event
import cloud/shells/turn
import eyg/ir/tree as ir
import eyg/parser
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
  let config = qcheck.default_config() |> qcheck.with_test_count(40)
  use #(steps, mode) <- qcheck.run(
    config,
    qcheck.tuple2(
      qcheck.generic_list(step(), qcheck.bounded_int(1, 6)),
      qcheck.bounded_int(1, 2),
    ),
  )
  use context <- helpers.context()
  let id = int.to_string(int.random(1_000_000_000))
  let shell = case mode {
    1 -> {
      let shell = shell_helpers.shell(context)
      let assert Ok(source) = parser.all_from_string(code(steps, server, id))
      let program = ir.map_annotation(source, fn(_) { Nil })
      let assert Ok(_) =
        shell_helpers.turn(context, shell, turn.Program(program))
      shell
    }
    _ -> {
      let shell = shell_helpers.shell(context)
      let assert Ok(_) =
        shell_helpers.run(context, shell, code(steps, server, id))
      shell
    }
  }
  let entries = shell_helpers.entries(context, shell)

  list.index_map(entries, fn(_, i) { i + 1 })
  |> list.each(fn(length) {
    let prefix = list.take(entries, length)
    let copy = shell_helpers.prefix(context, shell, length)
    // Another process changes the box before the shell is resumed.
    case length % 2 {
      0 -> {
        let assert Ok(_) =
          box.change(context, copy.box, fn(root) {
            file_system.write(root, "/other.txt", <<int.to_string(length):utf8>>)
          })
        Nil
      }
      _ -> Nil
    }
    let before = counts(server, steps, id)
    let assert Ok(#(Ok("{}"), [])) = shell_helpers.run(context, copy, "{}")
    let after = counts(server, steps, id)

    let copied = shell_helpers.entries(context, copy)
    let assert [_, ..] = list.filter(copied, is_finished)
    assert list.take(copied, length) == prefix

    list.zip(steps, list.zip(before, after))
    |> list.index_map(fn(step_counts, i) {
      let #(step, #(before, after)) = step_counts
      let sent = after - before
      let expected = case requested(entries, length, path(id, i)), step {
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

fn is_finished(entry) {
  case entry {
    event.Output(stop: event.Finished(..), ..) -> True
    _ -> False
  }
}

type Requested {
  Answered
  // The prefix ends with the request, `rejected` if the changes before it were.
  Pending(rejected: Bool)
  NotRequested
}

fn requested(entries, length, path) {
  case
    list.drop_while(
      list.index_map(entries, fn(entry, i) { #(entry, i) }),
      fn(entry) {
        case entry.0 {
          event.Output(stop: event.Requested(request), ..) ->
            request.path != path
          _ -> True
        }
      },
    )
  {
    [#(event.Output(change:, ..), i), ..] if i < length ->
      case i + 1 >= length, change {
        True, event.Rejected(_) -> Pending(rejected: True)
        True, _ -> Pending(rejected: False)
        False, event.Rejected(_) -> Pending(rejected: True)
        False, _ -> Answered
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
