import cloud/beam/execute
import cloud/beam/file_system
import cloud/discord/discord
import cloud/discord/event
import cloud/schedule
import cloud/session
import cloud/slack/slack
import cloud/test_helpers
import cloud/trigger
import gleam/dict
import gleam/erlang/process
import gleam/string
import gleam/time/timestamp
import simplifile

pub fn main_right_on_trigger_still_checks_test() {
  let assert Ok(code) = simplifile.read("right_on.eyg")
  let assert Ok(#([_], _)) =
    trigger.prepare(
      [#("Right on", code)],
      discord.trigger_type(),
      test_helpers.state(),
    )
}

pub fn main_slack_right_on_trigger_still_checks_test() {
  let assert Ok(code) = simplifile.read("right_on_slack.eyg")
  let assert Ok(#([_], _)) =
    trigger.prepare(
      [#("Right on", code)],
      slack.trigger_type(),
      test_helpers.state(),
    )
}

pub fn main_cron_returns_a_message_and_queues_each_deadline_once_test() {
  let now = timestamp.from_unix_seconds(59)
  let assert Ok(#([scheduled], state)) =
    schedule.prepare(
      [
        schedule.Config(
          "tick",
          "* * * * *",
          "(_) -> { {session_id: \"test\", payload: Code(\"1\")} }",
        ),
      ],
      now,
      test_helpers.state(),
    )
  assert scheduled.next == timestamp.from_unix_seconds(60)
  let assert Ok(runtime) = schedule.runtime(state)
  let sessions = process.new_subject()
  let now = timestamp.from_unix_seconds(60)
  let #(schedules, runtime) =
    schedule.dispatch_due([scheduled], now, sessions, runtime)
  let assert Ok(session.Message("test", session.Code("1"), _)) =
    process.receive(sessions, 0)
  let assert [scheduled] = schedules
  assert scheduled.next == timestamp.from_unix_seconds(120)
  let _ = schedule.dispatch_due(schedules, now, sessions, runtime)
  assert process.receive(sessions, 0) == Error(Nil)
}

pub fn startup_trigger_checks_the_native_event_and_unit_return_test() {
  let assert Error(reason) =
    trigger.prepare(
      [#("invalid", "(event) -> { event.channel_name }")],
      discord.trigger_type(),
      test_helpers.state(),
    )
  assert string.contains(reason, "Trigger invalid")
}

pub fn startup_trigger_uses_main_file_policy_test() {
  let code =
    "(event) -> {
    let result = perform WriteFile({path: \"/skills/blocked\", contents: !string_to_binary(event.channel_name)})
    let _ = match result {
      Error(reason) -> { perform StandardOut(reason) }
      Ok(_) -> { perform StandardOut(\"unexpected write\") }
    }
    {}
  }"
  let assert Ok(#([function], state)) =
    trigger.prepare(
      [#("write", code)],
      discord.trigger_type(),
      test_helpers.state(),
    )
  let assert Ok(policy_source) = simplifile.read("policy.eyg")
  let assert #(Ok(policy), state) = execute.load_policy(policy_source, state)
  let output = process.new_subject()
  let value = event.to_eyg("noise", event.MessageCreate("m", "c", "rocket"))
  let #(result, _, files) =
    execute.call(
      function,
      value,
      state,
      policy,
      file_system.new(dict.new()),
      process.send(output, _),
    )
  assert result == Ok(Nil)
  assert process.receive(output, 0)
    == Ok(execute.StandardOut("Writing to /skills is denied by policy"))
  let assert Error(_) = file_system.read(files, "/skills/blocked", 0, 100)
}
