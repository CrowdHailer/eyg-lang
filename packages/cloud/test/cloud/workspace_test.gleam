import cloud/artifacts
import cloud/channel
import cloud/config
import cloud/connection
import cloud/connections/github
import cloud/data
import cloud/execute_test
import cloud/plugins/chat_input
import cloud/test_helpers
import cloud/workspace
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None}
import gleam/string
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool

const general = channel.Conversation("chat", "C1", None)

fn message(id, text) {
  channel.Incoming(general, native_message(id, text, False))
}

fn native_message(id, text, own) {
  chat_input.posted(chat_message(id, text, own))
}

fn chat_message(id, text, own) {
  let author = case own {
    True -> chat_input.Author("cloud", "cloud", True)
    False -> chat_input.Author("U1", "alice", False)
  }
  chat_input.Message(id, "C1", None, author, text)
}

fn reaction(message, by, emoji) {
  channel.Incoming(general, chat_input.reacted(message, by, emoji))
}

/// A platform that records everything posted to it.
fn platform() {
  let posts = process.new_subject()
  let outbound =
    channel.Outbound(
      input_type: chat_input.input_type(),
      post: fn(conversation, text) {
        process.send(posts, #(conversation, text))
        Ok("posted")
      },
      channel_name: fn(id) {
        case id {
          "C2" -> "notes"
          _ -> "general"
        }
      },
      channels: fn() { Ok([#("C1", "general"), #("C2", "notes")]) },
    )
  #(outbound, posts)
}

fn run_call(code) {
  tool.Call(
    id: "call",
    function: tool.FunctionCall(
      name: "run",
      arguments: dict.from_list([#("code", utils.String(code))]),
    ),
  )
}

/// A model that answers every turn the same way and reports the inputs it saw.
fn model(completions) {
  let seen = process.new_subject()
  let completer = fn(_llm, _context) {
    fn(history) {
      let assert [last, ..] = history
      case last {
        chat.UserMessage(text:, ..) -> {
          process.send(seen, text)
          let assert [first, ..] = completions
          Ok(first)
        }
        _ -> Ok(chat.Completion("", "done", []))
      }
    }
  }
  #(completer, seen)
}

/// Tests share a process, a session left over from one test that crashes later,
/// when that test's output has closed, must not fail the test running then.
fn detach(workspace) {
  let assert Ok(pid) = process.subject_owner(workspace)
  process.unlink(pid)
}

/// Stop a workspace and its sessions, so schedules do not outlive the test.
fn stop(workspace) {
  let assert Ok(pid) = process.subject_owner(workspace)
  process.kill(pid)
}

fn start(completions) {
  start_file("test/fixtures/chat_workspace.eyg", completions)
}

fn start_file(file, completions) {
  let load =
    config.loader(file, test_helpers.state(), fn(_) { Error("no secrets") })
  let #(completer, seen) = model(completions)
  let assert Ok(artifacts) = artifacts.start("http://cloud.test")
  let assert Ok(workspace) = workspace.start_with(load, artifacts, completer)
  detach(workspace)
  let #(outbound, posts) = platform()
  process.send(workspace, workspace.Connect("chat", outbound))
  #(workspace, posts, seen)
}

pub fn messages_go_to_the_agent_test() {
  let #(workspace, posts, seen) =
    start([chat.Completion("", "", [run_call("perform Post(\"hello alice\")")])])
  process.send(workspace, workspace.Inbound(message("m1", "hi there")))
  let assert Ok(input) = process.receive(seen, 1000)
  assert input == "[#general] alice (message m1): hi there"
  assert process.receive(posts, 1000) == Ok(#(general, "hello alice"))
}

pub fn the_agent_chooses_not_to_post_test() {
  let #(workspace, posts, seen) =
    start([chat.Completion("", "Nothing to add.", [])])
  process.send(workspace, workspace.Inbound(message("m1", "lunch?")))
  let assert Ok(_) = process.receive(seen, 1000)
  assert process.receive(posts, 200) == Error(Nil)
}

pub fn own_messages_are_ignored_test() {
  let #(workspace, _posts, seen) = start([chat.Completion("", "", [])])
  let mine = channel.Incoming(general, native_message("m1", "hello", True))
  process.send(workspace, workspace.Inbound(mine))
  assert process.receive(seen, 200) == Error(Nil)
}

pub fn direct_invocations_run_with_the_shell_test() {
  let #(workspace, posts, seen) = start([chat.Completion("", "", [])])
  let code = message("m1", "```eyg\n!int_add(1, 2)\n```")
  process.send(workspace, workspace.Inbound(code))
  let thread = channel.Conversation(..general, thread: option.Some("m1"))
  assert process.receive(posts, 1000) == Ok(#(thread, "3"))
  // The agent sees the invocation with the next message.
  assert process.receive(seen, 200) == Error(Nil)
  process.sleep(50)
  process.send(workspace, workspace.Inbound(message("m2", "thanks")))
  let assert Ok(input) = process.receive(seen, 1000)
  let assert [observed, latest] = string.split(input, "\n\n")
  assert string.ends_with(observed, "It returned: 3")
  assert latest == "[#general] alice (message m2): thanks"
}

pub fn new_forgets_the_conversation_test() {
  let assert Ok(artifacts) = artifacts.start("http://cloud.test")
  let load =
    config.loader(
      "test/fixtures/chat_workspace.eyg",
      test_helpers.state(),
      fn(_) { Error("no secrets") },
    )
  let histories = process.new_subject()
  let completer = fn(_llm, _context) {
    fn(history) {
      process.send(histories, list.length(history))
      Ok(chat.Completion("", "ok", []))
    }
  }
  let assert Ok(workspace) = workspace.start_with(load, artifacts, completer)
  detach(workspace)
  let #(outbound, posts) = platform()
  process.send(workspace, workspace.Connect("chat", outbound))
  let send = fn(id, text) {
    process.send(workspace, workspace.Inbound(message(id, text)))
  }
  send("m1", "one")
  assert process.receive(histories, 1000) == Ok(1)
  send("m2", "two")
  assert process.receive(histories, 1000) == Ok(3)
  send("m3", "/new")
  let assert Ok(#(
    _,
    "Started a new conversation, earlier messages are forgotten.",
  )) = process.receive(posts, 1000)
  send("m4", "three")
  assert process.receive(histories, 1000) == Ok(1)
}

fn custom_loader(handle, policy) {
  fn() {
    let assert Ok(config) =
      config.load(
        "test/fixtures/chat_workspace.eyg",
        test_helpers.state(),
        fn(_) { Error("no secrets") },
      )
    let channel =
      execute_test.evaluate(
        "let on_message = "
        <> handle
        <> "\nlet channel = (_) -> { {handle: match { ChatPosted(message) -> { on_message(message) } ChatReacted(_) -> { [] } }, channel_shell: "
        <> policy
        <> "} }\nchannel",
      )
    Ok(config.Workspace(..config, channel:))
  }
}

pub fn handler_posts_are_subject_to_the_channel_policy_test() {
  let #(completer, seen) = model([chat.Completion("", "done", [])])
  let load =
    custom_loader(
      "(event) -> { [Post({thread: Some(event.id), text: event.text})] }",
      "{post: (text) -> { Pass(!string_append(\"checked: \", text)) }, ..cloud.reject_all}",
    )
  let assert Ok(artifacts) = artifacts.start("http://cloud.test")
  let assert Ok(workspace) = workspace.start_with(load, artifacts, completer)
  detach(workspace)
  let #(outbound, posts) = platform()
  process.send(workspace, workspace.Connect("chat", outbound))
  process.send(workspace, workspace.Inbound(message("m1", "hello")))
  assert process.receive(posts, 1000)
    == Ok(#(
      channel.Conversation(..general, thread: option.Some("m1")),
      "checked: hello",
    ))
  assert process.receive(seen, 100) == Error(Nil)
}

pub fn rejected_handler_post_never_reaches_the_plugin_test() {
  let #(completer, seen) = model([chat.Completion("", "done", [])])
  let load =
    custom_loader(
      "(event) -> { [Post({thread: None({}), text: event.text})] }",
      "cloud.reject_all",
    )
  let assert Ok(artifacts) = artifacts.start("http://cloud.test")
  let assert Ok(workspace) = workspace.start_with(load, artifacts, completer)
  detach(workspace)
  let #(outbound, posts) = platform()
  process.send(workspace, workspace.Connect("chat", outbound))
  process.send(workspace, workspace.Inbound(message("m1", "hello")))
  assert process.receive(posts, 200) == Error(Nil)
  assert process.receive(seen, 100) == Error(Nil)
}

pub fn handler_selects_sessions_and_observations_test() {
  let histories = process.new_subject()
  let completer = fn(_, _) {
    fn(history) {
      process.send(histories, history)
      Ok(chat.Completion("", "done", []))
    }
  }
  let load =
    custom_loader(
      "(event) -> { [Observe({session: Some(event.id), text: \"observed\"}), Input({session: Some(event.id), text: event.text})] }",
      "cloud.reject_all",
    )
  let assert Ok(artifacts) = artifacts.start("http://cloud.test")
  let assert Ok(workspace) = workspace.start_with(load, artifacts, completer)
  detach(workspace)
  let #(outbound, _) = platform()
  process.send(workspace, workspace.Connect("chat", outbound))
  process.send(workspace, workspace.Inbound(message("s1", "first")))
  let assert Ok([chat.UserMessage(text: "observed\n\nfirst", ..)]) =
    process.receive(histories, 1000)
  process.send(workspace, workspace.Inbound(message("s2", "other")))
  let assert Ok([chat.UserMessage(text: "observed\n\nother", ..)]) =
    process.receive(histories, 1000)
  process.send(workspace, workspace.Inbound(message("s1", "again")))
  let assert Ok(history) = process.receive(histories, 1000)
  assert list.length(history) == 3
}

pub fn channels_write_under_their_root_test() {
  let #(workspace, posts, _seen) = start([chat.Completion("", "", [])])
  let notes = channel.Conversation("chat", "C2", None)
  let thread = channel.Conversation(..notes, thread: option.Some("m1"))
  let run = fn(id, code) {
    let message =
      channel.Incoming(
        notes,
        native_message(id, "```eyg\n" <> code <> "\n```", False),
      )
    process.send(workspace, workspace.Inbound(message))
  }
  run(
    "m1",
    "perform WriteFile({path: \"/skills/x.md\", contents: !string_to_binary(\"x\")})",
  )
  let assert Ok(#(_, denied)) = process.receive(posts, 1000)
  assert denied == "Error(\"write_file denied by policy: /skills/x.md\")"
  run(
    "m1",
    "let _ = perform MakeDirectory(\"/channels\")\nperform MakeDirectory(\"/channels/notes\")",
  )
  let assert Ok(#(_, _)) = process.receive(posts, 1000)
  run(
    "m1",
    "perform WriteFile({path: \"channels/notes/todo.md\", contents: !string_to_binary(\"buy milk\")})",
  )
  assert process.receive(posts, 1000) == Ok(#(thread, "Ok({})"))
  let read =
    message(
      "m2",
      "```eyg\nperform ReadFile({path: \"/channels/notes/todo.md\", offset: 0, limit: 100})\n```",
    )
  process.send(workspace, workspace.Inbound(read))
  let assert Ok(#(_, text)) = process.receive(posts, 1000)
  assert string.contains(text, "Ok(")
}

pub fn agent_actions_import_modules_from_the_session_file_system_test() {
  let code =
    "let _ = perform WriteFile({path: \"/program.eyg\", contents: !string_to_binary(\"42\")})\nlet answer = import \"/program.eyg\"\nperform Post(!int_to_string(answer))"
  let #(workspace, posts, _) =
    start([chat.Completion("", "", [run_call(code)])])
  process.send(workspace, workspace.Inbound(message("m1", "run the module")))
  assert process.receive(posts, 1000) == Ok(#(general, "42"))
}

pub fn changes_to_files_read_are_noted_test() {
  let #(workspace, posts, seen) = start([chat.Completion("", "Noted.", [])])
  let notes = channel.Conversation("chat", "C2", None)
  // The notes agent is given the skills index, so it has read the greet skill.
  let hello = channel.Incoming(notes, native_message("m1", "hello", False))
  process.send(workspace, workspace.Inbound(hello))
  let assert Ok(_) = process.receive(seen, 1000)
  process.sleep(100)
  // The general channel changes the skill.
  let edit =
    message(
      "m2",
      "```eyg\nperform WriteFile({path: \"/skills/greet/SKILL.md\", contents: !string_to_binary(\"updated\")})\n```",
    )
  process.send(workspace, workspace.Inbound(edit))
  let assert Ok(_) = process.receive(posts, 1000)
  process.sleep(100)
  let again = channel.Incoming(notes, native_message("m3", "again", False))
  process.send(workspace, workspace.Inbound(again))
  let assert Ok(input) = process.receive(seen, 1000)
  assert string.contains(input, "/skills/greet/SKILL.md changed by #general")
  assert string.ends_with(input, "[#notes] alice (message m3): again")
}

fn invoke(workspace, id, code) {
  let invocation = message(id, "```eyg\n" <> code <> "\n```")
  process.send(workspace, workspace.Inbound(invocation))
}

fn thread(id) {
  channel.Conversation(..general, thread: option.Some(id))
}

pub fn reaction_triggers_run_in_the_thread_test() {
  let #(workspace, posts, _seen) = start([chat.Completion("", "", [])])
  let link = chat_message("m1", "see https://eyg.run", False)
  let bob = chat_input.Author("U2", "bob", False)
  process.send(workspace, workspace.Inbound(reaction(link, bob, "books")))
  assert process.receive(posts, 1000)
    == Ok(#(thread("m1"), "summary of see https://eyg.run"))
  // Other reactions do not match.
  process.send(workspace, workspace.Inbound(reaction(link, bob, "eyes")))
  assert process.receive(posts, 200) == Error(Nil)
}

pub fn triggers_can_delegate_to_a_subagent_test() {
  let #(workspace, posts, _seen) =
    start([chat.Completion("", "EYG is a language.", [])])
  let question = message("m1", "research: what is eyg?")
  process.send(workspace, workspace.Inbound(question))
  assert process.receive(posts, 1000)
    == Ok(#(thread("m1"), "EYG is a language."))
}

pub fn programs_manage_triggers_test() {
  let #(workspace, posts, _seen) = start([chat.Completion("", "", [])])
  invoke(
    workspace,
    "m1",
    "perform AddTrigger({name: \"polite\", pattern: match { ChatPosted(p) -> { !string_starts_with(p.text, \"please\") } | (_) -> { False({}) } }, script: (_event) -> { perform Post(\"of course\") }})",
  )
  assert process.receive(posts, 1000) == Ok(#(thread("m1"), "Ok({})"))
  process.send(workspace, workspace.Inbound(message("m2", "please help")))
  assert process.receive(posts, 1000) == Ok(#(thread("m2"), "of course"))

  invoke(workspace, "m3", "perform StopTrigger(\"polite\")")
  let assert Ok(#(_, "Ok({})")) = process.receive(posts, 1000)
  process.send(workspace, workspace.Inbound(message("m4", "please again")))
  assert process.receive(posts, 300) == Error(Nil)

  invoke(workspace, "m5", "perform ListTriggers({})")
  let assert Ok(#(_, listed)) = process.receive(posts, 1000)
  assert string.contains(listed, "polite (stopped)")

  invoke(workspace, "m6", "perform DeleteTrigger(\"polite\")")
  let assert Ok(#(_, "Ok({})")) = process.receive(posts, 1000)
  invoke(workspace, "m7", "perform DeleteTrigger(\"polite\")")
  let assert Ok(#(_, "Error(\"no trigger named polite\")")) =
    process.receive(posts, 1000)
}

pub fn patterns_cannot_perform_effects_test() {
  let #(workspace, posts, _seen) = start([chat.Completion("", "", [])])
  invoke(
    workspace,
    "m1",
    "perform AddTrigger({name: \"sneaky\", pattern: (event) -> { let _ = perform Post(\"sneaky\")\nTrue({}) }, script: \"perform Post(\\\"ran\\\")\"})",
  )
  assert process.receive(posts, 1000) == Ok(#(thread("m1"), "Ok({})"))
  process.send(workspace, workspace.Inbound(message("m2", "hello")))
  assert process.receive(posts, 300) == Error(Nil)
}

pub fn timeouts_message_the_session_test() {
  let #(workspace, posts, seen) =
    start([chat.Completion("", "", [run_call("perform Post(\"Oven!\")")])])
  invoke(
    workspace,
    "m1",
    "perform Timeout({name: \"remind\", after: 50, message: \"check the oven\"})",
  )
  assert process.receive(posts, 1000) == Ok(#(thread("m1"), "Ok({})"))
  let assert Ok(input) = process.receive(seen, 1000)
  assert string.ends_with(input, "[timeout remind] check the oven")
  assert process.receive(posts, 1000) == Ok(#(general, "Oven!"))
}

pub fn crons_repeat_until_cancelled_test() {
  let #(workspace, posts, seen) = start([chat.Completion("", "Quiet.", [])])
  invoke(
    workspace,
    "m1",
    "perform Cron({name: \"tick\", schedule: \"* * * * * *\", message: \"tick\"})",
  )
  assert process.receive(posts, 1000) == Ok(#(thread("m1"), "Ok({})"))
  let assert Ok(first) = process.receive(seen, 2000)
  assert string.ends_with(first, "[cron tick] tick")
  let assert Ok(second) = process.receive(seen, 2000)
  assert string.ends_with(second, "[cron tick] tick")
  invoke(workspace, "m2", "perform CancelSchedule(\"tick\")")
  assert process.receive(posts, 1000) == Ok(#(thread("m2"), "Ok({})"))
  // A turn may already be queued, after that no more.
  let _ = process.receive(seen, 1100)
  assert process.receive(seen, 1500) == Error(Nil)
  stop(workspace)
}

pub fn configured_crons_message_existing_sessions_test() {
  let #(workspace, _posts, seen) =
    start_file("test/fixtures/cron_workspace.eyg", [
      chat.Completion("", "Quiet.", []),
    ])
  // There is no session for general until a message is posted.
  assert process.receive(seen, 1500) == Error(Nil)
  process.send(workspace, workspace.Inbound(message("m1", "morning")))
  let assert Ok(_) = process.receive(seen, 1000)
  let assert Ok(input) = process.receive(seen, 2000)
  assert input == "[cron standup] Time for standup."
  stop(workspace)
}

pub fn artifacts_belong_to_their_channel_test() {
  let #(workspace, posts, _seen) = start([chat.Completion("", "", [])])
  let save =
    "perform Artifact({name: \"plan\", bundle: [{path: \"index.html\", media_type: \"text/html\", content: !string_to_binary(\"<h1>Plan</h1>\")}]})"
  invoke(workspace, "m1", save)
  assert process.receive(posts, 1000)
    == Ok(#(
      thread("m1"),
      "Ok({url: \"http://cloud.test/artifacts/plan/\", version: 1})",
    ))
  let notes = channel.Conversation("chat", "C2", None)
  let attempt =
    channel.Incoming(
      notes,
      native_message("n1", "```eyg\n" <> save <> "\n```", False),
    )
  process.send(workspace, workspace.Inbound(attempt))
  let assert Ok(#(_, refused)) = process.receive(posts, 1000)
  assert string.contains(refused, "belongs to #general")
  invoke(workspace, "m2", "perform ShareArtifact(\"plan\")")
  let assert Ok(#(_, "Ok(\"http://cloud.test/artifacts/plan/\")")) =
    process.receive(posts, 1000)
  process.send(workspace, workspace.Inbound(attempt))
  let assert Ok(#(_, updated)) = process.receive(posts, 1000)
  assert string.contains(updated, "version: 2")
}

fn issue_event(id, title, live) {
  let value =
    data.tagged(
      "GitHubIssue",
      data.record([
        #("connection", data.string("github")),
        #("repository", data.string("eyg/eyg")),
        #("actor", data.string("alice")),
        #("url", data.string("https://github.com/eyg/eyg/issues/1")),
        #("action", data.string("opened")),
        #("number", data.int(1)),
        #("title", data.string(title)),
        #("body", data.string("")),
        #("labels", data.strings([])),
      ]),
    )
  connection.Event("github", id, value, "issue " <> title, live)
}

pub fn connection_events_run_the_channels_triggers_test() {
  let #(workspace, posts, seen) = start([chat.Completion("", "", [])])
  process.send(workspace, workspace.Observed(issue_event("e1", "Old", False)))
  process.send(workspace, workspace.Observed(issue_event("e2", "Crash", True)))
  // Posted in the channel, not a thread, and the agent is not told.
  assert process.receive(posts, 1000) == Ok(#(general, "New issue: Crash"))
  assert process.receive(posts, 200) == Error(Nil)
  assert process.receive(seen, 200) == Error(Nil)
}

pub fn programs_read_the_event_log_test() {
  let #(workspace, posts, _seen) = start([chat.Completion("", "", [])])
  process.send(workspace, workspace.Observed(issue_event("e1", "Old", False)))
  invoke(
    workspace,
    "m1",
    "match perform Events(\"github\") {\n  Ok(events) -> { !list_fold(events, 0, (_event, count) -> { !int_add(count, 1) }) }\n  Error(reason) -> { 0 }\n}",
  )
  assert process.receive(posts, 1000) == Ok(#(thread("m1"), "1"))
  invoke(workspace, "m2", "perform Events(\"nope\")")
  assert process.receive(posts, 1000)
    == Ok(#(thread("m2"), "Error(\"no connection named nope\")"))
}

fn sign(body) {
  "sha256="
  <> {
    crypto.hmac(<<body:utf8>>, crypto.Sha256, <<"s3cret":utf8>>)
    |> bit_array.base16_encode
    |> string.lowercase
  }
}

pub fn signed_webhooks_run_triggers_test() {
  let #(workspace, posts, _seen) = start([chat.Completion("", "", [])])
  let body =
    "{\"action\":\"opened\",\"repository\":{\"full_name\":\"eyg/eyg\"},\"sender\":{\"login\":\"bob\"},\"issue\":{\"number\":3,\"title\":\"Docs\"}}"
  let delivery = fn(connection, signature) {
    github.Delivery(connection, "issues", "d1", signature, body)
  }
  let call = fn(delivery) {
    process.call(workspace, 1000, workspace.Webhook(delivery, _))
  }
  assert call(delivery("github", "sha256=bad")) == Error("invalid signature")
  assert call(delivery("nope", sign(body))) == Error("no connection named nope")
  assert process.receive(posts, 200) == Error(Nil)
  assert call(delivery("github", sign(body))) == Ok(Nil)
  assert process.receive(posts, 1000) == Ok(#(general, "New issue: Docs"))
}
