//// One real model request, one pure EYG program, one expected value.

import argv
import envoy
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug as type_debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state as interpreter
import eyg/interpreter/value
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/debug as parse_debug
import gleam/dict
import gleam/dynamic/decode
import gleam/fetch
import gleam/http/response
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import oas/generator/utils
import ogre/origin
import overlay/agent
import overlay/eval/deadline
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/ollama
import overlay/llm/provider/openai
import overlay/llm/tool
import overlay/tools/run
import plinthx/node/process
import simplifile

pub const fibonacci =
  "Calculate the sum of the first 20 Fibonacci numbers, starting with 1, 1. Use an EYG program to calculate the sum and return it as an integer."

/// Parse and type-check before evaluating. There is no effect handler.
pub fn evaluate(code: String) -> Result(interpreter.Value(Nil), String) {
  use source <- result.try(
    parser.all_from_string(code)
    |> result.map_error(parse_debug.describe),
  )
  let source = ir.map_annotation(source, fn(_) { Nil })
  let context = infer.pure()
  let context = infer.Context(..context, env: [#("context", t.record([]))])
  let analysis = infer.check_with_references(context, dict.new(), source)
  case infer.all_errors(analysis) {
    [] ->
      expression.execute(source, [#("context", value.unit())])
      |> result.map_error(fn(debug) { simple_debug.describe(debug.0) })
    errors ->
      errors
      |> list.map(fn(error) { type_debug.reason(error.1) })
      |> string.join("\n")
      |> Error
  }
}

/// Tool arguments are the submitted program; prose is never graded.
pub fn program(
  completion: chat.Completion(tool.Call),
) -> Result(String, String) {
  case completion.tool_calls {
    [tool.Call(function: tool.FunctionCall("run", arguments), ..)] ->
      decode.run(
        utils.fields_to_dynamic(arguments),
        decode.field("code", decode.string, decode.success),
      )
      |> result.replace_error("run requires a code string")
    _ -> Error("expected exactly one run tool call")
  }
}

pub fn check(
  code: String,
  expected: interpreter.Value(Nil),
) -> Result(Nil, String) {
  use actual <- result.try(evaluate(code))
  case actual == expected {
    True -> Ok(Nil)
    False ->
      Error(
        "expected "
        <> simple_debug.inspect(expected)
        <> ", got "
        <> simple_debug.inspect(actual),
      )
  }
}

pub fn configuration(description) {
  case string.split_once(description, ":") {
    Ok(#("ollama", model)) ->
      envoy.get("OLLAMA_API_KEY")
      |> result.replace_error("OLLAMA_API_KEY is required")
      |> result.map(fn(key) {
        provider.Llm(provider.Ollama(ollama.cloud(key)), model)
      })
    Ok(#("ollama-local", model)) ->
      Ok(provider.Llm(provider.Ollama(ollama.local()), model))
    Ok(#("openai-local", model)) -> {
      let raw =
        envoy.get("OVERLAY_EVAL_OPENAI_ORIGIN")
        |> result.unwrap("http://127.0.0.1:7210")
      use origin <- result.try(
        origin.from_string_strict(raw)
        |> result.replace_error("invalid OVERLAY_EVAL_OPENAI_ORIGIN"),
      )
      Ok(provider.Llm(
        provider.OpenAI(
          openai.Config(
            origin:,
            path: "/v1/chat/completions",
            api_key: None,
            headers: [],
          ),
        ),
        model,
      ))
    }
    _ ->
      Error("use ollama:<model>, ollama-local:<model> or openai-local:<model>")
  }
}

pub fn request(description, root) {
  use llm <- result.try(configuration(description))
  use syntax <- result.try(read(root <> "/guides/syntax.md"))
  use builtins <- result.map(read(root <> "/guides/builtins_reference.md"))
  #(
    llm,
    provider.completion_request(
      llm,
      provider.Context(pure_prompt(syntax, builtins), [run.spec()]),
      [chat.UserMessage(fibonacci, [])],
    ),
  )
}

fn read(path) {
  simplifile.read(path)
  |> result.replace_error("cannot read " <> path)
}

pub fn main() {
  let request = case argv.load().arguments {
    [model] -> request(model, "../..")
    [model, root] -> request(model, root)
    _ ->
      Error(
        "usage: gleam run -m overlay/eval/pure -- ollama:<model> [repo-root]",
      )
  }
  case request {
    Error(reason) -> promise.resolve(finish(Error(reason)))
    Ok(#(llm, request)) -> {
      use response <- promise.map(
        fetch.send_bits(request)
        |> promise.try_await(fetch.read_text_body)
        |> deadline.within(
          300_000,
          fetch.NetworkError("model request timed out after 300s"),
        ),
      )
      let result = {
        use response <- result.try(result.map_error(response, string.inspect))
        use completion <- result.try(provider.completion_response(
          llm,
          response.set_body(response, <<response.body:utf8>>),
        ))
        use code <- result.try(program(completion))
        io.println(code)
        check(code, value.Integer(17_710))
      }
      finish(result)
    }
  }
}

fn finish(result) {
  case result {
    Ok(Nil) -> io.println("PASS: Fibonacci sum = 17710")
    Error(reason) -> {
      io.println_error("FAIL: " <> reason)
      exit_code(1)
    }
  }
}

fn exit_code(code: Int) -> Nil {
  case process.get() {
    Ok(process) -> process.set_exit_code(process, code)
    Error(Nil) -> Nil
  }
}

fn pure_prompt(syntax, builtins) {
  agent.introduction <> "
This environment evaluates pure programs. No effects or imports are available.
The EYG guides are included below; there is no need to fetch them.
Return one program using the run tool.
# Context
The context is the empty record {}.
# Syntax guide
" <> syntax <> "

# Builtins reference

" <> builtins
}
