import cloud/artifacts
import cloud/beam/execute
import cloud/channel
import cloud/config
import cloud/plugins/chat_input
import cloud/session
import cloud/test_helpers
import cloud/workspace
import filepath
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None}
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool
import simplifile

const general = #("C1", None)

fn incoming(address: #(String, option.Option(String)), value) {
  channel.Incoming("chat", address.0, address.1, value)
}

fn message(id, text) {
  incoming(general, native_message(id, text, False))
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
  incoming(general, chat_input.reacted(message, by, emoji))
}

/// A platform that records everything posted to it.
fn platform() {
  let posts = process.new_subject()
  let outbound =
    channel.Outbound(
      input_type: chat_input.input_type(),
      post: fn(channel, reply, text) {
        process.send(posts, #(#(channel, reply), text))
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
    |> test_helpers.isolated
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

pub fn ordinary_agent_replies_are_delivered_directly_test() {
  let #(workspace, posts, seen) =
    start([chat.Completion("", "Nothing to add.", [])])
  process.send(workspace, workspace.Inbound(message("m1", "lunch?")))
  let assert Ok(_) = process.receive(seen, 1000)
  assert process.receive(posts, 1000) == Ok(#(general, "Nothing to add."))
}

pub fn own_messages_are_ignored_test() {
  let #(workspace, _posts, seen) = start([chat.Completion("", "", [])])
  let mine = incoming(general, native_message("m1", "hello", True))
  process.send(workspace, workspace.Inbound(mine))
  assert process.receive(seen, 200) == Error(Nil)
}

pub fn direct_invocations_run_with_the_shell_test() {
  let #(workspace, posts, seen) = start([chat.Completion("", "", [])])
  let code = message("m1", "```eyg\n!int_add(1, 2)\n```")
  process.send(workspace, workspace.Inbound(code))
  let thread = #(general.0, option.Some("m1"))
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
    |> test_helpers.isolated
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
  assert process.receive(posts, 1000) == Ok(#(general, "ok"))
  send("m2", "two")
  assert process.receive(histories, 1000) == Ok(3)
  assert process.receive(posts, 1000) == Ok(#(general, "ok"))
  send("m3", "/new")
  let assert Ok(#(
    _,
    "Started a new conversation, earlier messages are forgotten.",
  )) = process.receive(posts, 1000)
  send("m4", "three")
  assert process.receive(histories, 1000) == Ok(1)
}

fn custom_loader(handle, policy) {
  let directory = test_helpers.directory()
  let assert Ok(base) = simplifile.resolve("test/fixtures/chat_workspace.eyg")
  let assert Ok(source) = simplifile.read(base)
  let source =
    string.replace(
      source,
      "./support.eyg",
      filepath.join(filepath.directory_name(base), "support.eyg"),
    )
  let source =
    "let make_base = (_) -> {\n"
    <> source
    <> "\n}\nlet base = make_base({})\nlet on_message = "
    <> handle
    <> "\n{files: \""
    <> filepath.directory_name(base)
    <> "/files\", channel: (_) -> { {on_input: match { ChatPosted(message) -> { on_message(message) } ChatReacted(_) -> { [] } }, channel_shell: "
    <> policy
    <> "} }, ..base}"
  let assert Ok(_) = simplifile.create_directory_all(directory)
  let file = directory <> "/workspace.eyg"
  let assert Ok(_) = simplifile.write(file, source)
  config.loader(file, test_helpers.state(), fn(_) { Error("no secrets") })
}

pub fn handler_posts_are_subject_to_the_channel_policy_test() {
  let #(completer, seen) = model([chat.Completion("", "done", [])])
  let load =
    custom_loader(
      "(event) -> { [Post({thread: Some(event.id), text: event.text})] }",
      "{post: (text) -> { Pass(!string_append(\"checked: \", text)) }, ..cloud.mock_all}",
    )
  let assert Ok(artifacts) = artifacts.start("http://cloud.test")
  let assert Ok(workspace) = workspace.start_with(load, artifacts, completer)
  detach(workspace)
  let #(outbound, posts) = platform()
  process.send(workspace, workspace.Connect("chat", outbound))
  process.send(workspace, workspace.Inbound(message("m1", "hello")))
  assert process.receive(posts, 1000)
    == Ok(#(#(general.0, option.Some("m1")), "checked: hello"))
  assert process.receive(seen, 100) == Error(Nil)
}

pub fn rejected_handler_post_never_reaches_the_plugin_test() {
  let #(completer, seen) = model([chat.Completion("", "done", [])])
  let load =
    custom_loader(
      "(event) -> { [Post({thread: None({}), text: event.text})] }",
      "cloud.mock_all",
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
      "cloud.mock_all",
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

pub fn selected_session_names_are_not_reply_destinations_test() {
  let #(completer, _) =
    model([chat.Completion("", "", [run_call("perform Post(\"answer\")")])])
  let load =
    custom_loader(
      "(event) -> { [Input({session: Some(\"research-task\"), text: event.text})] }",
      "{post: (text) -> { Pass(text) }, ..cloud.mock_all}",
    )
  let assert Ok(artifacts) = artifacts.start("http://cloud.test")
  let assert Ok(workspace) = workspace.start_with(load, artifacts, completer)
  detach(workspace)
  let #(outbound, posts) = platform()
  process.send(workspace, workspace.Connect("chat", outbound))
  let address = #("C1", option.Some("native-thread"))
  process.send(
    workspace,
    workspace.Inbound(incoming(address, native_message("m1", "hello", False))),
  )
  assert process.receive(posts, 1000) == Ok(#(address, "answer"))
}

pub fn final_agent_and_script_values_do_not_require_post_permission_test() {
  let #(completer, _) = model([chat.Completion("", "direct reply", [])])
  let load =
    custom_loader(
      "(event) -> { [Submit({session: None({}), reply: None({}), text: event.text, description: event.text})] }",
      "cloud.mock_all",
    )
  let assert Ok(artifacts) = artifacts.start("http://cloud.test")
  let assert Ok(workspace) = workspace.start_with(load, artifacts, completer)
  detach(workspace)
  let #(outbound, posts) = platform()
  process.send(workspace, workspace.Connect("chat", outbound))
  process.send(workspace, workspace.Inbound(message("m1", "hello")))
  assert process.receive(posts, 1000) == Ok(#(general, "direct reply"))
  process.send(workspace, workspace.Inbound(message("m2", "```eyg\n42\n```")))
  assert process.receive(posts, 1000) == Ok(#(general, "42"))
  process.send(
    workspace,
    workspace.Inbound(message("m3", "```eyg\nperform Post(\"forbidden\")\n```")),
  )
  let assert Ok(#(_, error)) = process.receive(posts, 1000)
  assert string.contains(error, "Policy") || string.contains(error, "policy")
  assert process.receive(posts, 50) == Error(Nil)
}

pub fn scripts_keep_selected_session_files_across_reply_destinations_test() {
  let #(completer, _) = model([chat.Completion("", "done", [])])
  let load =
    custom_loader(
      "(event) -> { [Run({session: Some(\"research-task\"), reply: Some(event.id), code: event.text, description: event.text})] }",
      "{post: (text) -> { Pass(text) }, read_file: (input) -> { Pass(input) }, write_file: (input) -> { Pass(input) }, ..cloud.mock_all}",
    )
  let assert Ok(artifacts) = artifacts.start("http://cloud.test")
  let assert Ok(workspace) = workspace.start_with(load, artifacts, completer)
  detach(workspace)
  let #(outbound, posts) = platform()
  process.send(workspace, workspace.Connect("chat", outbound))
  process.send(
    workspace,
    workspace.Inbound(message(
      "m1",
      "perform WriteFile({path: \"/answer.eyg\", contents: !string_to_binary(\"42\")})",
    )),
  )
  assert process.receive(posts, 1000) == Ok(#(thread("m1"), "Ok({})"))
  process.send(
    workspace,
    workspace.Inbound(message("m2", "import \"/answer.eyg\"")),
  )
  assert process.receive(posts, 1000) == Ok(#(thread("m2"), "42"))
}

pub fn reset_posts_to_the_requested_reply_not_the_selected_session_test() {
  let #(completer, _) = model([chat.Completion("", "done", [])])
  let load =
    custom_loader(
      "(event) -> { [Submit({session: Some(\"research-task\"), reply: Some(event.id), text: event.text, description: event.text})] }",
      "{post: (text) -> { Pass(text) }, ..cloud.mock_all}",
    )
  let assert Ok(artifacts) = artifacts.start("http://cloud.test")
  let assert Ok(workspace) = workspace.start_with(load, artifacts, completer)
  detach(workspace)
  let #(outbound, posts) = platform()
  process.send(workspace, workspace.Connect("chat", outbound))
  process.send(workspace, workspace.Inbound(message("m1", "/new")))
  assert process.receive(posts, 1000)
    == Ok(#(
      thread("m1"),
      "Started a new conversation, earlier messages are forgotten.",
    ))
}

pub fn channels_have_private_files_and_still_enforce_path_policies_test() {
  let #(workspace, posts, _seen) = start([chat.Completion("", "", [])])
  let notes = #("C2", None)
  let thread = #(notes.0, option.Some("m1"))
  let run = fn(id, code) {
    let message =
      incoming(notes, native_message(id, "```eyg\n" <> code <> "\n```", False))
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
  assert string.contains(text, "No such file or directory")
}

pub fn agent_actions_import_modules_from_the_session_file_system_test() {
  let code =
    "let _ = perform WriteFile({path: \"/program.eyg\", contents: !string_to_binary(\"42\")})\nlet answer = import \"/program.eyg\"\nperform Post(!int_to_string(answer))"
  let #(workspace, posts, _) =
    start([chat.Completion("", "", [run_call(code)])])
  process.send(workspace, workspace.Inbound(message("m1", "run the module")))
  assert process.receive(posts, 1000) == Ok(#(general, "42"))
}

pub fn invocations_and_agents_use_the_same_selected_session_files_test() {
  let #(workspace, posts, _) =
    start([
      chat.Completion("", "", [
        run_call(
          "let answer = import \"/answer.eyg\"\nperform Post(!int_to_string(answer))",
        ),
      ]),
    ])
  invoke(
    workspace,
    "m1",
    "perform WriteFile({path: \"/answer.eyg\", contents: !string_to_binary(\"42\")})",
  )
  let assert Ok(_) = process.receive(posts, 1000)
  process.send(workspace, workspace.Inbound(message("m2", "read the answer")))
  assert process.receive(posts, 1000) == Ok(#(general, "42"))
}

pub fn installations_with_equal_channel_ids_keep_distinct_outbound_routes_test() {
  let #(workspace, _, _) =
    start([chat.Completion("", "", [run_call("perform Post(\"hello\")")])])
  let #(first, first_posts) = platform()
  let #(second, second_posts) = platform()
  process.send(workspace, workspace.Connect("chat/team-a", first))
  process.send(workspace, workspace.Connect("chat/team-b", second))
  process.send(
    workspace,
    workspace.Inbound(channel.at(message("m1", "first"), "chat/team-a")),
  )
  process.send(
    workspace,
    workspace.Inbound(channel.at(message("m2", "second"), "chat/team-b")),
  )
  assert process.receive(first_posts, 1000) == Ok(#(#("C1", None), "hello"))
  assert process.receive(second_posts, 1000) == Ok(#(#("C1", None), "hello"))
  let assert Error(_) =
    process.call(workspace, 1000, workspace.ChannelHost("general", _))
  let assert Ok(_) =
    process.call(workspace, 1000, workspace.ChannelHost("chat/team-a:C1", _))
}

pub fn web_timeouts_retain_their_files_policy_and_reply_after_rebinding_test() {
  let load =
    config.loader(
      "test/fixtures/chat_workspace.eyg",
      test_helpers.state(),
      fn(_) { Error("no secrets") },
    )
    |> test_helpers.isolated
  let #(completer, _) =
    model([
      chat.Completion("", "", [
        run_call(
          "match perform WriteFile({path: \"/answer.eyg\", contents: !string_to_binary(\"43\")}) { Ok(_) -> { let answer = import \"/answer.eyg\"\nperform Post(!int_to_string(answer)) } Error(reason) -> { perform Post(reason) } }",
        ),
      ]),
    ])
  let assert Ok(artifacts) = artifacts.start("http://cloud.test")
  let assert Ok(executor) = session.start_configured()
  let assert Ok(workspace) =
    workspace.start_on(load, artifacts, completer, executor, "test")
  detach(workspace)
  let #(outbound, posts) = platform()
  process.send(workspace, workspace.Connect("chat", outbound))
  let assert Ok(#(_, host)) =
    process.call(workspace, 1000, workspace.WebHost("ada", "general", _))
  let scheduled = process.new_subject()
  process.send(
    executor,
    session.WithFiles("web:ada", None, fn(result) {
      let assert Ok(execution) = result
      let #(run, execution) =
        execute.checked(
          "perform WriteFile({path: \"/answer.eyg\", contents: !string_to_binary(\"42\")})",
          [],
          execute.unrestricted(),
          host,
          execution,
        )
      let assert Ok(_) = run.result
      let assert Ok(_) = host.schedules.timeout("read", 60_000, "read my file")
      process.send(scheduled, Nil)
      #("scheduled a read", execution)
    }),
  )
  let assert Ok(_) = process.receive(scheduled, 1000)
  let assert Ok(_) =
    process.call(workspace, 1000, workspace.WebHost("ada", "notes", _))
  process.send(workspace, workspace.Fire("web:ada", "read"))
  assert process.receive(posts, 1000) == Ok(#(general, "43"))
  stop(workspace)
}

pub fn changes_in_another_session_do_not_affect_agent_context_test() {
  let #(workspace, posts, seen) = start([chat.Completion("", "Noted.", [])])
  let notes = #("C2", None)
  // The notes agent is given the skills index, so it has read the greet skill.
  let hello = incoming(notes, native_message("m1", "hello", False))
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
  let again = incoming(notes, native_message("m3", "again", False))
  process.send(workspace, workspace.Inbound(again))
  let assert Ok(input) = process.receive(seen, 1000)
  assert input == "[#notes] alice (message m3): again"
}

fn invoke(workspace, id, code) {
  let invocation = message(id, "```eyg\n" <> code <> "\n```")
  process.send(workspace, workspace.Inbound(invocation))
}

fn thread(id) {
  #(general.0, option.Some(id))
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
  let #(workspace, posts, seen) = start([chat.Completion("", "", [])])
  invoke(
    workspace,
    "m1",
    "perform Cron({name: \"tick\", schedule: \"* * * * *\", message: \"tick\"})",
  )
  assert process.receive(posts, 1000) == Ok(#(thread("m1"), "Ok({})"))
  let due = timestamp.add(timestamp.system_time(), duration.seconds(60))
  process.send(workspace, workspace.Tick(due))
  let assert Ok(first) = process.receive(seen, 2000)
  assert string.ends_with(first, "[cron tick] tick")
  process.send(workspace, workspace.Tick(due))
  assert process.receive(seen, 50) == Error(Nil)
  process.send(
    workspace,
    workspace.Tick(timestamp.add(due, duration.seconds(60))),
  )
  let assert Ok(second) = process.receive(seen, 2000)
  assert string.ends_with(second, "[cron tick] tick")
  invoke(workspace, "m2", "perform CancelSchedule(\"tick\")")
  assert process.receive(posts, 1000) == Ok(#(thread("m2"), "Ok({})"))
  process.send(
    workspace,
    workspace.Tick(timestamp.add(due, duration.seconds(120))),
  )
  assert process.receive(seen, 50) == Error(Nil)
  stop(workspace)
}

pub fn configured_crons_message_existing_sessions_test() {
  let #(workspace, _posts, seen) =
    start_file("test/fixtures/cron_workspace.eyg", [
      chat.Completion("", "Quiet.", []),
    ])
  // There is no session for general until a message is posted.
  let due = timestamp.add(timestamp.system_time(), duration.seconds(60))
  process.send(workspace, workspace.Tick(due))
  assert process.receive(seen, 50) == Error(Nil)
  process.send(workspace, workspace.Inbound(message("m1", "morning")))
  let assert Ok(_) = process.receive(seen, 1000)
  process.send(
    workspace,
    workspace.Tick(timestamp.add(due, duration.seconds(60))),
  )
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
  let notes = #("C2", None)
  let attempt =
    incoming(notes, native_message("n1", "```eyg\n" <> save <> "\n```", False))
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
