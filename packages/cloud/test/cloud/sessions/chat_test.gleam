import cloud/beam/execute
import cloud/box
import cloud/file_system
import cloud/helpers
import cloud/overlay
import cloud/server
import cloud/session_helpers
import cloud/sessions/event
import cloud/sessions/turn
import gleam/erlang/process
import gleam/http
import gleam/list
import gleam/string
import overlay/llm/chat

const write =
  "perform WriteFile({path: \"/a.txt\", contents: !string_to_binary(\"a\")})"

const read = "perform ReadFile({path: \"/a.txt\", offset: 0, limit: 10})"

pub fn reply_after_running_tool_calls_test() {
  use context <- helpers.context()
  let server = server.start(process.new_subject())
  let #(context, session) = session_helpers.chat(context, server)
  let message = "run:" <> write <> "\n---\n" <> read
  let assert Ok(#(Ok(reply), [])) =
    session_helpers.send(context, session, message)
  assert string.starts_with(reply, "Ok(")
  // Each completion is a stop, the changes before it are merged first.
  let assert [
    event.Configured("test"),
    event.Sent(sent, _),
    event.Resumed(start),
    event.Asked([chat.UserMessage(asked, [])], _),
    event.Answered(execute.Completed(Ok(_))),
    event.Resumed(_),
    event.Asked([chat.ToolResultMessage(..)], written),
    event.Answered(execute.Completed(Ok(_))),
    event.Resumed(after),
    event.Asked([chat.ToolResultMessage(text: result, ..)], _),
    event.Answered(execute.Completed(Ok(_))),
    event.Resumed(_),
    event.Returned(Ok(returned), [], _),
    event.Finished(Ok(finished), [], end),
  ] = session_helpers.events(context, session)
  assert sent == message && asked == message
  assert written == after && start != after && end == after
  assert reply == result && reply == returned && reply == finished
  assert 3 == server.count_requests(server, http.Post, "/api/chat")
  let assert Ok(home) = box.latest(context, session.box)
  assert Ok(Ok(<<"a">>))
    == execute.files(file_system.read(home.root, "/a.txt"), context.state)
}

pub fn continue_the_chat_test() {
  use context <- helpers.context()
  let server = server.start(process.new_subject())
  let #(context, session) = session_helpers.chat(context, server)
  let assert Ok(#(Ok("hello #1"), [])) =
    session_helpers.send(context, session, "hello")
  // Code can be run in the session, it is not part of the chat.
  let assert Ok(#(Ok("1"), [])) = session_helpers.run(context, session, "1")
  let assert Ok(#(Ok("again #2"), [])) =
    session_helpers.send(context, session, "again")
}

pub fn messages_need_an_llm_test() {
  use context <- helpers.context()
  let session = session_helpers.session(context)
  let assert Error(box.Invalid(["the session does not chat with an llm"])) =
    session_helpers.send(context, session, "hello")
}

const invalid =
  "perform WriteFile({path: \"/retry.eyg\", contents: !string_to_binary(\"let x =\")})"

const valid =
  "perform WriteFile({path: \"/retry.eyg\", contents: !string_to_binary(\"1\")})"

// The recover-invalid-module case: the llm writes an invalid module and repairs it when told.
pub fn repair_a_rejected_change_test() {
  use context <- helpers.context()
  let server = server.start(process.new_subject())
  let #(context, session) = session_helpers.chat(context, server)
  let assert Ok(#(Ok(_), [])) =
    session_helpers.send(
      context,
      session,
      "run:" <> invalid <> "\n---\n" <> valid,
    )
  let events = session_helpers.events(context, session)
  let assert Ok(rejection) =
    list.find_map(events, fn(event) {
      case event {
        event.Answered(execute.Rejected(reason)) -> Ok(reason)
        _ -> Error(Nil)
      }
    })
  assert string.starts_with(rejection, "File changes rejected\n/retry.eyg")
  // The llm was told and asked again.
  let assert Ok(_) =
    list.find(events, fn(event) {
      case event {
        event.Asked([chat.UserMessage(text, _)], _) ->
          string.starts_with(text, overlay.rejected_prefix)
        _ -> False
      }
    })
  let assert Ok(home) = box.latest(context, session.box)
  assert Ok(Ok(<<"1">>))
    == execute.files(file_system.read(home.root, "/retry.eyg"), context.state)
  // The rejection is replayed.
  let log = session_helpers.export(context, session)
  let assert Ok(_) = session_helpers.import_(context, session.box, log)
}

pub fn repairs_are_limited_test() {
  use context <- helpers.context()
  let server = server.start(process.new_subject())
  let #(context, session) = session_helpers.chat(context, server)
  let message = "run:" <> string.join(list.repeat(invalid, 5), "\n---\n")
  let assert Ok(#(Error(reason), [])) =
    session_helpers.send(context, session, message)
  assert string.starts_with(reason, "File changes rejected")
  // The first attempt and three repairs.
  assert 4 == server.count_requests(server, http.Post, "/api/chat")
  let assert Ok(home) = box.latest(context, session.box)
  let assert Ok(Error(_)) =
    execute.files(file_system.read(home.root, "/retry.eyg"), context.state)
  // The next message's chat says the last reply failed.
  let assert Ok(chat.UserMessage(failed, [])) =
    turn.conversation(session_helpers.events(context, session)) |> list.last
  assert string.starts_with(
    failed,
    "The last reply failed.\nFile changes rejected",
  )
}
