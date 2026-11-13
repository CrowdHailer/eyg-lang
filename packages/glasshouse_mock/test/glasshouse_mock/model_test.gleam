import glasshouse/session
import glasshouse/usage
import glasshouse_mock/model
import gleam/bit_array
import gleam/dict
import gleam/http/response
import gleam/list
import gleam/result
import gleam/string
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/provider/ollama
import overlay/llm/tool

const script =
  "{\"rules\": [
  {\"prompt\": \"notes\", \"system\": \"be brief\", \"steps\": [{\"text\": \"Brief.\"}]},
  {\"prompt\": \"notes\", \"steps\": [{\"code\": \"read\"}, {\"code\": \"write\"}, {\"text\": \"The notes were {{result}}\"}]}
]}"

fn rules() {
  let assert Ok(rules) = model.parse(script)
  rules
}

pub fn steps_follow_tool_results_test() {
  let rules = rules()
  let user = #("user", "Update the NOTES please")
  assert model.next(rules, "", [user]) == model.Code("read")
  assert model.next(rules, "", [user, #("assistant", ""), #("tool", "a")])
    == model.Code("write")
  assert model.next(rules, "", [
      user,
      #("assistant", ""),
      #("tool", "a"),
      #("assistant", ""),
      #("tool", "b"),
    ])
    == model.Answer("The notes were b")
}

pub fn a_new_prompt_starts_again_test() {
  let rules = rules()
  let messages = [
    #("user", "notes"),
    #("tool", "a"),
    #("tool", "b"),
    #("tool", "c"),
  ]
  assert model.next(rules, "", messages) == model.Answer("Done.")
  assert model.next(rules, "", list.append(messages, [#("user", "notes")]))
    == model.Code("read")
}

pub fn rules_can_depend_on_the_system_prompt_test() {
  assert model.next(rules(), "Please Be Brief.", [#("user", "notes")])
    == model.Answer("Brief.")
}

pub fn unmatched_prompts_are_explained_test() {
  let assert model.Answer(text) = model.next(rules(), "", [#("user", "hi")])
  assert text == "This scripted model has no rule for \"hi\"."
}

pub fn invalid_scripts_are_rejected_test() {
  let assert Error(_) = model.parse("{\"rules\": [{\"prompt\": \"x\"}]}")
}

fn request(history) {
  let tools = [tool.Tool("run", "Run EYG code", [])]
  ollama.completion_request(
    ollama.local(),
    "scripted",
    "system",
    history,
    tools,
  ).body
}

pub fn replies_are_read_by_the_ollama_provider_test() {
  let body = request([chat.UserMessage(text: "update the notes", images: [])])
  let assert Ok(reply) = model.reply(rules(), body, 1_791_889_260_000)
  let response = response.new(200) |> response.set_body(<<reply:utf8>>)
  let assert Ok(completion) = ollama.completion_response(response)
  let assert [tool.Call(function: tool.FunctionCall(name:, arguments:), ..)] =
    completion.tool_calls
  assert name == "run"
  assert dict.get(arguments, "code") == Ok(utils.String("read"))
}

pub fn streamed_replies_are_read_by_the_ollama_provider_test() {
  let assert Ok(text) =
    request([chat.UserMessage(text: "update the notes", images: [])])
    |> bit_array.to_string
  let body = <<
    string.replace(text, "\"stream\":false", "\"stream\":true"):utf8,
  >>
  let assert Ok(reply) = model.reply(rules(), body, 0)
  let #(chunks, remaining) = ollama.completion_chunk_parse(<<>>, <<reply:utf8>>)
  assert remaining == <<>>
  let completion = chat.append_chunks(chat.fresh(), chunks)
  let assert [_] = completion.tool_calls
}

pub fn usage_is_estimated_test() {
  let body = request([chat.UserMessage(text: "update the notes", images: [])])
  let assert Ok(reply) = model.reply(rules(), body, 0)
  let session.Usage(input:, output:) = usage.from_response(<<reply:utf8>>)
  assert input == usage.estimate(bit_array.to_string(body) |> result.unwrap(""))
  // The code of the first step is "read".
  assert output == 1
}
