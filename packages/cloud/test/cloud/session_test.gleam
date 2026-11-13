import cloud/beam/execute
import cloud/config
import cloud/plugins/chat_input
import cloud/session
import cloud/session_store
import cloud/test_helpers
import eyg/interpreter/value as v
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/ollama
import simplifile

fn setup(name, directory, histories) {
  session.Setup(
    name:,
    directory:,
    seed: None,
    channel: config.ChannelInfo(
      "chat",
      "C1",
      "general",
      chat_input.input_type(),
    ),
    location: "test",
    load: config.loader(
      "test/fixtures/chat_workspace.eyg",
      test_helpers.state(),
      fn(_) { Error("no secrets") },
    ),
    host: execute.configuration_host(fn(_) { Error("no secrets") }),
    complete: fn(_, _) {
      fn(history) {
        process.send(histories, history)
        Ok(chat.Completion("", "done", []))
      }
    },
  )
}

fn barrier(executor, id) {
  let done = process.new_subject()
  session.send(
    executor,
    id,
    session.Run(fn(_, execution) {
      process.send(done, Nil)
      #(None, execution)
    }),
  )
  let assert Ok(Nil) = process.receive(done, 1000)
  Nil
}

fn configured(executor, setup: session.Setup) {
  session.submit(
    executor,
    setup.name,
    setup,
    session.Run(fn(_, execution) { #(None, execution) }),
    None,
  )
  setup.name
}

fn stop(executor) {
  let assert Ok(pid) = process.subject_owner(executor)
  process.unlink(pid)
  process.kill(pid)
}

pub fn all_sessions_execute_in_one_process_and_mailbox_order_test() {
  let assert Ok(executor) = session.start_configured()
  let histories = process.new_subject()
  let a = configured(executor, setup("a", test_helpers.directory(), histories))
  let b = configured(executor, setup("b", test_helpers.directory(), histories))
  let started = process.new_subject()
  let finished = process.new_subject()
  let release = process.new_subject()
  // Make a subject owned by the central actor, so the first job can block deterministically.
  session.send(
    executor,
    a,
    session.Run(fn(_, execution) {
      let gate = process.new_subject()
      process.send(release, gate)
      process.send(started, process.self())
      let assert Ok(Nil) = process.receive(gate, 1000)
      process.send(finished, "a")
      #(None, execution)
    }),
  )
  let assert Ok(gate) = process.receive(release, 1000)
  let assert Ok(pid_a) = process.receive(started, 1000)
  session.send(
    executor,
    b,
    session.Run(fn(_, execution) {
      process.send(started, process.self())
      process.send(finished, "b")
      #(None, execution)
    }),
  )
  assert process.receive(started, 50) == Error(Nil)
  process.send(gate, Nil)
  assert process.receive(finished, 1000) == Ok("a")
  assert process.receive(finished, 1000) == Ok("b")
  assert process.receive(started, 1000) == Ok(pid_a)
  assert process.subject_owner(executor) == Ok(pid_a)
  stop(executor)
}

pub fn history_observations_files_and_metadata_survive_restart_test() {
  let directory = test_helpers.directory()
  let histories = process.new_subject()
  let config = setup("stable", directory, histories)
  let assert Ok(first) = session.start_configured()
  let handle = configured(first, config)
  session.send(first, handle, session.Input("remember me"))
  let assert Ok(_) = process.receive(histories, 1000)
  session.send(
    first,
    handle,
    session.Run(fn(host, execution) {
      let #(run, execution) =
        execute.checked(
          "perform WriteFile({path: \"/bytes\", contents: bytes})",
          [#("bytes", v.Binary(<<0, 255, 42>>))],
          execute.unrestricted(),
          host,
          execution,
        )
      let assert Ok(_) = run.result
      #(Some("a script ran"), execution)
    }),
  )
  barrier(first, handle)
  stop(first)
  let assert Ok(metadata) = simplifile.read(directory <> "/session.json")
  assert string.contains(metadata, "stable")
  let assert Ok(second) = session.start_configured()
  let restored = configured(second, config)
  session.send(second, restored, session.Input("again"))
  let assert Ok(history) = process.receive(histories, 1000)
  assert list.length(history) == 3
  let assert [chat.UserMessage(text, _), ..] = history
  assert text == "a script ran\n\nagain"
  let read = process.new_subject()
  session.send(
    second,
    restored,
    session.Run(fn(host, execution) {
      process.send(read, host.files.read("/bytes"))
      #(None, execution)
    }),
  )
  assert process.receive(read, 1000) == Ok(Ok(<<0, 255, 42>>))
  session.send(second, restored, session.Reset)
  session.send(second, restored, session.Input("new conversation"))
  let assert Ok(history) = process.receive(histories, 1000)
  assert list.length(history) == 1
  session.send(
    second,
    restored,
    session.Run(fn(host, execution) {
      process.send(read, host.files.read("/bytes"))
      #(None, execution)
    }),
  )
  assert process.receive(read, 1000) == Ok(Ok(<<0, 255, 42>>))
  stop(second)
}

pub fn session_files_are_private_even_with_identical_channel_ids_test() {
  let assert Ok(executor) = session.start_configured()
  let histories = process.new_subject()
  let root = test_helpers.directory()
  let a =
    configured(
      executor,
      setup(
        "slack/team-a:C1",
        session_store.directory(root, "slack/team-a:C1"),
        histories,
      ),
    )
  let b =
    configured(
      executor,
      setup(
        "slack/team-b:C1",
        session_store.directory(root, "slack/team-b:C1"),
        histories,
      ),
    )
  session.send(
    executor,
    a,
    session.Run(fn(host, execution) {
      let #(run, execution) =
        execute.checked(
          "perform WriteFile({path: \"/secret\", contents: !string_to_binary(\"private\")})",
          [],
          execute.unrestricted(),
          host,
          execution,
        )
      let assert Ok(_) = run.result
      #(None, execution)
    }),
  )
  let read = process.new_subject()
  session.send(
    executor,
    b,
    session.Run(fn(host, execution) {
      process.send(read, host.files.read("/secret"))
      #(None, execution)
    }),
  )
  let assert Ok(Error(_)) = process.receive(read, 1000)
  stop(executor)
}

pub fn main_code_entry_point_keeps_private_roots_and_fresh_scope_test() {
  let assert Ok(started) =
    session.start(
      test_helpers.state().origin,
      provider.Llm(provider.Ollama(ollama.local()), "unused"),
    )
  let outputs = process.new_subject()
  let send = fn(id, code) {
    process.send(
      started.data,
      session.Message(id, session.Code(code), process.send(outputs, _)),
    )
  }
  send("a", "let x = 42 x")
  assert process.receive(outputs, 1000) == Ok(execute.StandardOut("42"))
  send("a", "x")
  let assert Ok(execute.StandardError(_)) = process.receive(outputs, 1000)
  send("a", "perform MakeDirectory(\"./skills\")")
  assert process.receive(outputs, 1000)
    == Ok(execute.StandardOut(
      "Error(\"Writing to /skills is denied by policy\")",
    ))
  send(
    "a",
    "let _ = perform WriteFile({path: \"/answer.eyg\", contents: !string_to_binary(\"42\")}) 0",
  )
  assert process.receive(outputs, 1000) == Ok(execute.StandardOut("0"))
  send("a", "import \"/answer.eyg\"")
  assert process.receive(outputs, 1000) == Ok(execute.StandardOut("42"))
  send("b", "import \"/answer.eyg\"")
  let assert Ok(execute.StandardError(_)) = process.receive(outputs, 1000)
  stop(started.data)
}

pub fn basic_sessions_restore_files_after_restart_test() {
  let root = test_helpers.directory()
  let llm = provider.Llm(provider.Ollama(ollama.local()), "unused")
  let assert Ok(first) =
    session.start_persistent(test_helpers.state().origin, llm, root)
  let outputs = process.new_subject()
  process.send(
    first.data,
    session.Message(
      "Slack:T:C",
      session.Code(
        "let _ = perform WriteFile({path: \"/answer.eyg\", contents: !string_to_binary(\"42\")}) 0",
      ),
      process.send(outputs, _),
    ),
  )
  assert process.receive(outputs, 1000) == Ok(execute.StandardOut("0"))
  stop(first.data)
  let assert Ok(second) =
    session.start_persistent(test_helpers.state().origin, llm, root)
  process.send(
    second.data,
    session.Message(
      "Slack:T:C",
      session.Code("import \"/answer.eyg\""),
      process.send(outputs, _),
    ),
  )
  assert process.receive(outputs, 1000) == Ok(execute.StandardOut("42"))
  stop(second.data)
}
