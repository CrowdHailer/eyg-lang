import eyg/embed/agent
import gleam/bit_array
import gleam/json
import hashi/board
import hashi/effect.{Bridge}
import hashi/fixture
import hashi/play
import overlay/llm/provider
import overlay/llm/provider/ollama
import simplifile

fn tool_call(code) {
  json.object([
    #("done", json.bool(True)),
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
  let #(shell, board) = state
  let result = play.run(shell, board, code)
  #(#(result.shell, result.board), play.report(result))
}

pub fn the_agent_plays_through_the_same_shell_test() {
  let assert Ok(library) = simplifile.read("library.eyg")
  let assert Ok(shell) = play.start(library)
  let llm = provider.Llm(provider.Ollama(ollama.local()), "test-model")
  let #(agent, _) = agent.ask(agent.new(llm, "play"), "join the top")
  let assert agent.Continue(state: #(_, board), runs: [#(_, "Ok({})")], ..) =
    agent.respond(
      agent,
      #(shell, fixture.corners()),
      tool_call("hashi.connect({x: 0, y: 0}, {x: 2, y: 0})"),
      run,
    )
  assert board.bridges(board) == [Bridge(from: #(0, 0), to: #(2, 0), count: 1)]
}
