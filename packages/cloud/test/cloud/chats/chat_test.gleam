import cloud/beam/execute
import cloud/box
import cloud/chat_helpers
import cloud/chats/chat
import cloud/chats/event
import cloud/data/db
import cloud/file_system
import cloud/helpers
import cloud/server
import cloud/shell_helpers
import gleam/erlang/process
import gleam/http
import gleam/list
import gleam/option.{Some}
import gleam/string
import overlay/llm/chat as llm
import pog

const write =
  "perform WriteFile({path: \"/a.txt\", contents: !string_to_binary(\"a\")})"

const read = "perform ReadFile({path: \"/a.txt\", offset: 0, limit: 10})"

pub fn reply_after_running_tool_calls_test() {
  use context <- helpers.context()
  let server = server.start(process.new_subject())
  let #(context, talk) = chat_helpers.chat(context, server)
  let message = "run:" <> write <> "\n---\n" <> read
  let assert Ok(Ok(reply)) = chat_helpers.send(context, talk, message)
  assert string.starts_with(reply, "Ok(")
  let assert [
    event.Sent(sent),
    event.Replied(llm.Completion(tool_calls: [first], ..)),
    event.Returned(first_id, Ok(_)),
    event.Replied(llm.Completion(tool_calls: [second], ..)),
    event.Returned(second_id, Ok(result)),
    event.Replied(llm.Completion(content: finished, tool_calls: [], ..)),
  ] = chat_helpers.entries(context, talk)
  assert sent == message
  assert first.id == first_id && second.id == second_id
  assert first_id != second_id
  assert reply == result && reply == finished
  assert 3 == server.count_requests(server, http.Post, "/api/chat")
  // Each call ran as the only turn of a shell of its own.
  let assert Ok(shells) = chat.shells(context, talk.id)
  assert [first_id, second_id]
    == list.filter_map(shells, fn(ran) { option.to_result(ran.1, Nil) })
    |> list.sort(string.compare)
  list.each(shells, fn(ran) {
    let assert [_, _] = shell_helpers.entries(context, ran.0)
  })
  let assert Ok(home) = box.latest(context, talk.box)
  assert Ok(Ok(<<"a">>))
    == execute.files(file_system.read(home.root, "/a.txt"), context.state)
}

pub fn tool_calls_run_at_the_same_time_test() {
  // The calls query the database at the same time, which one connection cannot.
  let context = helpers.pool_context()
  let arrived = process.new_subject()
  let server = server.start(arrived)
  let #(context, talk) = chat_helpers.chat(context, server)
  let slow = server.fetch(server, "GET", "/slow")
  let write_b =
    "perform WriteFile({path: \"/b.txt\", contents: !string_to_binary(\"b\")})"
  let message = "all:let _ = " <> slow <> "\n" <> write <> "\n---\n" <> write_b
  let done = process.new_subject()
  process.spawn(fn() {
    process.send(done, chat_helpers.send(context, talk, message))
  })
  // The second call finishes while the first waits for its response.
  let assert Ok(release) = process.receive(arrived, 5000)
  helpers.wait_until(
    fn() {
      let assert Ok(home) = box.latest(context, talk.box)
      execute.files(file_system.read(home.root, "/b.txt"), context.state)
      == Ok(Ok(<<"b">>))
    },
    500,
  )
  process.send(release, Nil)
  let assert Ok(Ok(Ok(reply))) = process.receive(done, 5000)
  let assert [_, _] = string.split(reply, "\n")
  let assert [
    event.Sent(_),
    event.Replied(llm.Completion(tool_calls: [_, _], ..)),
    event.Returned(_, Ok(_)),
    event.Returned(_, Ok(_)),
    event.Replied(llm.Completion(tool_calls: [], ..)),
  ] = chat_helpers.entries(context, talk)
  let assert Ok(home) = box.latest(context, talk.box)
  assert Ok(Ok(<<"a">>))
    == execute.files(file_system.read(home.root, "/a.txt"), context.state)
}

pub fn a_rejected_change_is_the_calls_result_test() {
  use context <- helpers.context()
  let server = server.start(process.new_subject())
  let #(context, talk) = chat_helpers.chat(context, server)
  let invalid =
    "perform WriteFile({path: \"/bad.eyg\", contents: !string_to_binary(\"let x =\")})"
  let assert Ok(Ok(reply)) = chat_helpers.send(context, talk, "run:" <> invalid)
  assert string.contains(reply, "File changes rejected")
  let assert Ok(home) = box.latest(context, talk.box)
  let assert Ok(Error(_)) =
    execute.files(file_system.read(home.root, "/bad.eyg"), context.state)
}

pub fn chats_need_a_configured_llm_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let assert Error(box.Invalid(["No llm is configured as missing"])) =
    chat.start(context, home.id, "missing")
}

pub fn a_failed_reply_is_told_to_the_llm_test() {
  use context <- helpers.context()
  let server = server.start(process.new_subject())
  let #(with_llm, talk) = chat_helpers.chat(context, server)
  // The llm is not configured any more.
  let assert Ok(Error("the llm test is not configured")) =
    chat_helpers.send(context, talk, "hello")
  let assert Ok(Ok("again #3")) = chat_helpers.send(with_llm, talk, "again")
  let assert [
    llm.UserMessage("hello", []),
    llm.UserMessage(failed, []),
    llm.UserMessage("again", []),
    llm.AssistantMessage(..),
  ] = event.conversation(chat_helpers.entries(context, talk))
  assert failed == "The last reply failed.\nthe llm test is not configured"
}

pub fn continue_after_stopping_at_any_entry_test() {
  use context <- helpers.context()
  let server = server.start(process.new_subject())
  let #(context, talk) = chat_helpers.chat(context, server)
  let code = fn(path) {
    "let _ = " <> server.fetch(server, "GET", path) <> "\n" <> write
  }
  let message = "run:" <> code("/one") <> "\n---\n" <> code("/two")
  let assert Ok(Ok(reply)) = chat_helpers.send(context, talk, message)
  let entries = chat_helpers.entries(context, talk)
  down_from(list.length(entries) - 1)
  |> list.each(fn(kept) {
    // As if the chat stopped after its first `kept` entries.
    let assert Ok(_) =
      "DELETE FROM chat_journal WHERE chat = $1 AND id NOT IN
        (SELECT id FROM chat_journal WHERE chat = $1 ORDER BY id LIMIT $2)"
      |> pog.query()
      |> pog.parameter(pog.text(talk.id))
      |> pog.parameter(pog.int(kept))
      |> db.execute(context.db)
    let assert Ok(Ok(again)) = chat.reply(context, talk)
    assert again == reply
    assert entries == chat_helpers.entries(context, talk)
  })
  // The code of each call ran once.
  assert 1 == server.count_requests(server, http.Get, "/one")
  assert 1 == server.count_requests(server, http.Get, "/two")
}

// The numbers from n down to 1.
fn down_from(n) {
  case n < 1 {
    True -> []
    False -> [n, ..down_from(n - 1)]
  }
}
