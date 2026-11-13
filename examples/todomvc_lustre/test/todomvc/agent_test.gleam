import eyg/embed/agent
import gleam/bit_array
import gleam/json
import overlay/llm/provider
import overlay/llm/provider/ollama
import todomvc/fixture
import todomvc/run
import todomvc/tasks.{Task}

fn tool_call(code) {
  json.object([
    #(
      "message",
      json.object([
        #("role", json.string("assistant")),
        #("content", json.string("")),
        #(
          "tool_calls",
          json.preprocessed_array([
            json.object([
              #(
                "function",
                json.object([
                  #("name", json.string("run")),
                  #("arguments", json.object([#("code", json.string(code))])),
                ]),
              ),
            ]),
          ]),
        ),
      ]),
    ),
  ])
  |> json.to_string
  |> bit_array.from_string
}

fn run(state, code) {
  let #(shell, tasks) = state
  let result = run.run(shell, tasks, code)
  #(#(result.shell, result.tasks), run.report(result))
}

pub fn the_agent_changes_tasks_through_the_same_shell_test() {
  let llm = provider.Llm(provider.Ollama(ollama.local()), "test-model")
  let #(agent, _) = agent.ask(agent.new(llm, "todo"), "add a task")
  let assert agent.Continue(state: #(_, tasks), runs: [#(_, "5")], ..) =
    agent.respond(
      agent,
      #(fixture.shell(), fixture.tasks()),
      tool_call("todos.add(\"Book dentist\")"),
      run,
    )
  let assert [_, _, _, _, Task(5, "Book dentist", False)] = tasks.all(tasks)
}
