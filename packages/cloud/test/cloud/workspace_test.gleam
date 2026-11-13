import cloud/channel
import cloud/config
import cloud/data
import cloud/execute_test
import cloud/test_helpers
import cloud/workspace
import eyg/analysis/type_/isomorphic as t
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
  data.record([
    #("id", data.string(id)),
    #("text", data.string(text)),
    #("own", data.bool(own)),
  ])
}

/// A platform that records everything posted to it.
fn platform() {
  let posts = process.new_subject()
  let outbound =
    channel.Outbound(
      input_type: t.record([
        #("id", t.String),
        #("text", t.String),
        #("own", t.boolean),
      ]),
      channels: fn() { Ok([#("C1", "general")]) },
      post: fn(conversation, text) {
        process.send(posts, #(conversation, text))
        Ok("posted")
      },
      channel_name: fn(_) { "general" },
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

fn start(completions) {
  let load =
    config.loader("test/fixtures/workspace_native.eyg", test_helpers.state())
  let #(completer, seen) = model(completions)
  let assert Ok(workspace) = workspace.start_with(load, completer)
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
  let load =
    config.loader("test/fixtures/workspace_native.eyg", test_helpers.state())
  let histories = process.new_subject()
  let completer = fn(_llm, _context) {
    fn(history) {
      process.send(histories, list.length(history))
      Ok(chat.Completion("", "ok", []))
    }
  }
  let assert Ok(workspace) = workspace.start_with(load, completer)
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
      config.load("test/fixtures/workspace_native.eyg", test_helpers.state())
    let channel =
      execute_test.evaluate(
        "(_) -> { {handle: " <> handle <> ", channel_shell: " <> policy <> "} }",
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
  let assert Ok(workspace) = workspace.start_with(load, completer)
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
  let assert Ok(workspace) = workspace.start_with(load, completer)
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
  let assert Ok(workspace) = workspace.start_with(load, completer)
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
