import eyg/cli/helpers
import eyg/cli/overlay
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/value
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{Some}
import loam/execute
import loam/sandbox
import loam/source
import overlay/llm/chat
import overlay/llm/provider/ollama

pub fn stdout_is_returned_and_still_written_to_the_terminal_test() {
  let #(result, sandbox) =
    run(
      "let _ = perform StandardOut(\"first\")
     let _ = perform StandardOut(\"second\\n\") 5",
      "(text) -> { Pass(text) }",
    )
  assert overlay.result_to_message("call", result)
    == chat.ToolResultMessage("call", "Output:\nfirstsecond\n\nResult:\n5", [])
  assert list.reverse(sandbox.stdout) == ["first", "second\n"]
}

fn run(code, stdout_policy) {
  let assert #(sandbox.Returned(#(result, _)), sandbox) =
    overlay.execute_call(
      call(code),
      "/",
      state(),
      policy(stdout_policy),
      value.unit(),
    )
    |> sandbox.run(sandbox.sandbox())
  #(result, sandbox)
}

fn state() {
  execute.State(helpers.config.client.origin, cache.empty())
}

fn call(code) {
  let encoded =
    json.object([
      #(
        "function",
        json.object([
          #("name", json.string("run")),
          #("arguments", json.object([#("code", json.string(code))])),
        ]),
      ),
    ])
  let assert Ok(call) =
    json.parse(json.to_string(encoded), ollama.tool_call_decoder())
  call.function
}

fn policy(stdout_policy) {
  let pass = evaluate("(value) -> { Pass(value) }")
  let fields =
    list.map(
      [
        "append_file", "create_key", "cwd", "delete_file", "env", "fetch",
        "make_directory", "now", "random", "read_directory", "read_file", "sign",
        "sleep", "standard_error", "standard_in", "write_file",
      ],
      fn(name) { #(name, pass) },
    )
  value.Record(
    dict.from_list([#("standard_out", evaluate(stdout_policy)), ..fields]),
  )
}

fn evaluate(code) {
  let assert Ok(source) = source.parse_input(code, source.Stdin)
  let assert Ok(#(Some(value), _)) = block.execute(source, [])
  value
}
