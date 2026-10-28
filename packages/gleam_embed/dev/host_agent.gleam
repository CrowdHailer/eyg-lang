//// Deterministic provider messages exercise an agent sharing the person's shell.
//// No network requests or model credentials are used.

import eyg/analysis/type_/isomorphic as t
import eyg/embed/agent
import eyg/embed/shell
import eyg/interpreter/value as v
import gleam/io
import gleam/option.{Some}
import overlay/llm/provider
import overlay/llm/provider/ollama

pub fn main() {
  let session = shell.new([#("Add", #(t.Integer, t.Integer))])
  let model = provider.Llm(provider.Ollama(ollama.local()), "protocol-fixture")
  let model = agent.new(model, "Count with the Add effect.")
  let #(model, _) = agent.ask(model, "Add five and remember it.")
  let handle = fn(total, _, lift) {
    let assert v.Integer(n) = lift
    Ok(#(total + n, v.Integer(total + n)))
  }
  let body = <<
    "{\"message\":{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"function\":{\"name\":\"run\",\"arguments\":{\"code\":\"let n = perform Add(5) n\"}}}]},\"done\":true}\n",
  >>
  let assert agent.Continue(model, #(session, 5), [#(_, "5")], _) =
    agent.respond(model, #(session, 0), body, agent.run_in_shell(handle))
  let body = <<
    "{\"message\":{\"role\":\"assistant\",\"content\":\"Counter is 5.\"},\"done\":true}\n",
  >>
  let assert agent.Answered(_, #(session, 5), "Counter is 5.") =
    agent.respond(model, #(session, 5), body, agent.run_in_shell(handle))
  let shell.Run(outcome:, ..) = shell.run(session, "!int_add(n, 1)", 5, handle)
  assert outcome == shell.Returned(Some(v.Integer(6)))
  io.println(
    "PASS protocol fixture: agent retained n=5; person reused it to return 6",
  )
}
