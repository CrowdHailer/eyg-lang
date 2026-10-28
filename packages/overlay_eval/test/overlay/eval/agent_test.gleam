import overlay/eval/agent

pub fn scripts_advance_after_replies_and_restart_at_next_turn_test() {
  let scripted =
    agent.scripted([
      [agent.Reply("", ["5"]), agent.Reply("five", [])],
      [agent.Reply("second", [])],
    ])
  let user = agent.Message("user", "first", [])
  let reply = agent.Message("assistant", "", ["5"])
  let result = agent.Message("tool", "5", [])
  assert agent.Reply("", ["5"]) == scripted(agent.Conversation("", [user]))
  assert agent.Reply("five", [])
    == scripted(agent.Conversation("", [user, reply, result]))
  assert agent.Reply("second", [])
    == scripted(agent.Conversation("", [user, reply, result, user]))
}

pub fn reads_the_actual_request_shape_test() {
  let assert Ok(conversation) =
    agent.conversation(<<
      "{\"messages\":[{\"role\":\"system\",\"content\":\"instructions\"},{\"role\":\"user\",\"content\":\"calculate\"}]}",
    >>)
  assert "instructions" == conversation.system
  assert [agent.Message("user", "calculate", [])] == conversation.messages
}
