import cloud/beam/execute
import cloud/box
import cloud/file_system
import cloud/helpers
import cloud/server
import cloud/session_helpers
import cloud/sessions/event
import gleam/erlang/process
import gleam/http
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

pub fn rejected_changes_end_the_chat_test() {
  use context <- helpers.context()
  let server = server.start(process.new_subject())
  let #(context, session) = session_helpers.chat(context, server)
  let invalid =
    "perform WriteFile({path: \"/bad.eyg\", contents: !string_to_binary(\"let x =\")})"
  let assert Ok(#(Error(reason), [])) =
    session_helpers.send(context, session, "run:" <> invalid)
  assert string.starts_with(reason, "File changes rejected")
  // The llm is not asked again after the change it made was rejected.
  assert 1 == server.count_requests(server, http.Post, "/api/chat")
}
