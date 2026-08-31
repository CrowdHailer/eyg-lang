import eyg/hub/cache
import eyg/hub/publisher
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/dict
import gleam/fetch
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import multiformats/cid/v1
import oas/generator/utils
import ogre/origin
import overlay/helpers.{init, new_reader, submit_first_prompt}
import overlay/llm/chat
import overlay/llm/tool
import overlay/web/provider_setup
import overlay/web/state.{State}
import overlay/web/tools
import pal/system
import untethered/ledger/schema
import untethered/substrate

pub fn init_loads_provider_settings_test() {
  let config = state.Config(origin: origin.https("eyg.test"))
  let #(state, actions) = state.init(config)
  let assert [system.GetSessionStorageItem("overlay.llm.provider", _), _] =
    actions
  assert True == state.provider_setup.restoring
}

pub fn provider_setup_selects_new_llm_test() {
  let config = state.Config(origin: origin.https("eyg.test"))
  let #(state, _) = state.init(config)
  let #(state, actions) =
    state.update(
      state,
      state.ProviderSetupMessage(provider_setup.SessionSettingsLoaded(
        "mistral",
        "mistral-small-latest",
        "test-key",
      )),
    )
  assert [] == actions
  assert "mistral-small-latest" == state.llm.model
  assert True == state.provider_setup.configured
}

pub fn submit_without_provider_opens_settings_test() {
  let config = state.Config(origin: origin.https("eyg.test"))
  let #(state, _) = state.init(config)
  let #(state, _) =
    state.update(
      state,
      state.ProviderSetupMessage(provider_setup.SessionSettingsLoaded(
        "",
        "",
        "",
      )),
    )
  let #(state, actions) = state.update(state, state.UserSubmittedPrompt)

  assert [] == actions
  assert True == state.provider_setup.settings_open
  let assert Some(_) = state.provider_setup.error
}

// input is separate component
pub fn submitting_empty_input_fails_test() {
  let #(state, actions) = submit_first_prompt("")
  assert [] == actions
  let assert Some(_) = state.input_error
}

pub fn submit_prompt_test() {
  let #(state, actions) = submit_first_prompt("hello")
  assert state.Asking([chat.UserMessage("hello", [])]) == state.status
  assert [] == state.history

  let assert [system.FetchStreamResponse(request, resume)] = actions
  assert "eyg.test" == request.host
  let assert Ok([_system, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #("user", "hello") == message
  let assert Ok([tool]) =
    json.parse_bits(request.body, helpers.ollama_tools_decoder())
  assert "run" == tool.name
  let assert [#("code", _, _)] = tool.parameters

  let assert system.Done(message) =
    resume(
      response.new(200)
      |> response.set_body(new_reader([], Ok(Nil)))
      |> Ok,
    )
  let #(state, actions) = state.update(state, message)
  let assert state.Streaming(_r, _, _) = state.status
  let assert [message] = state.history
  assert chat.UserMessage(text: "hello", images: []) == message

  let assert [system.ReadChunk(_reader, resume)] = actions

  let assert system.Done(message) =
    resume(Ok(Some(helpers.ollama_chunk_encode("Hi there"))))

  let #(state, actions) = state.update(state, message)
  let assert state.Streaming(_r, _, _) = state.status
  let assert [system.ReadChunk(_, resume)] = actions
  let assert system.Done(message) = resume(Ok(None))

  let #(state, actions) = state.update(state, message)
  assert state.Waiting == state.status
  assert "" == state.input
  let assert [llm_message, _message] = state.history
  assert chat.AssistantMessage("", "Hi there", []) == llm_message
  assert [] == actions
}

pub fn cant_submit_if_busy_test() {
  let state =
    State(
      ..init(),
      status: state.Asking([chat.UserMessage("Hi there", [])]),
      input: "something",
    )
  let #(state, actions) = state.update(state, state.UserSubmittedPrompt)
  let assert Some(_) = state.input_error
  assert [] == actions
}

pub fn started_streaming_while_not_asking_test() {
  let state = init()
  let #(s2, actions) =
    state.update(state, state.LlmStartedStreaming(new_reader([], Ok(Nil))))
  assert s2 == state
  assert [] == actions
}

pub fn interrupted_stream_test() {
  let #(state, actions) = submit_first_prompt("hello")
  let assert [system.FetchStreamResponse(_request, resume)] = actions
  let response =
    Ok(response.new(200) |> response.set_body(new_reader([], Ok(Nil))))
  let assert system.Done(message) = resume(response)
  let #(state, actions) = state.update(state, message)
  let assert [system.ReadChunk(_reader, resume)] = actions
  let assert system.Done(message) = resume(Error(fetch.NetworkError("Testing")))
  let #(state, actions) = state.update(state, message)
  let assert Some(_) = state.input_error
  assert [] == actions
}

pub fn streamed_completion_while_not_streaming_test() {
  let state = init()
  let #(s2, actions) =
    state.update(state, state.LlmStreamedCompletion([], <<>>))
  assert s2 == state
  assert [] == actions
}

// TODO invalid chunks from parsing

pub fn preserves_partial_stream_chunks_test() {
  let #(state, actions) = submit_first_prompt("hello")
  let assert [system.FetchStreamResponse(_request, resume)] = actions
  let response =
    Ok(response.new(200) |> response.set_body(new_reader([], Ok(Nil))))
  let assert system.Done(message) = resume(response)
  let #(state, actions) = state.update(state, message)
  let assert [system.ReadChunk(_reader, resume)] = actions

  let first = bit_array.from_string("{\"message\":{\"content\":\"Hi")
  let assert system.Done(message) = resume(Ok(Some(first)))
  let #(state, actions) = state.update(state, message)
  let assert state.Streaming(_, completion, remaining) = state.status
  assert "" == completion.content
  assert first == remaining
  let assert [system.ReadChunk(_reader, resume)] = actions

  let second = bit_array.from_string(" there\"}}\n")
  let assert system.Done(message) = resume(Ok(Some(second)))
  let #(state, _actions) = state.update(state, message)
  let assert state.Streaming(_, completion, <<>>) = state.status
  assert "Hi there" == completion.content
}

pub fn network_error_from_provider_test() {
  let #(state, actions) = submit_first_prompt("hello")
  let assert [system.FetchStreamResponse(_request, resume)] = actions
  let response = Error(fetch.NetworkError("Testing"))
  let assert system.Done(message) = resume(response)
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  let assert Some(_) = state.input_error
}

pub fn denied_error_from_provider_test() {
  let #(state, actions) = submit_first_prompt("hello")
  let assert [system.FetchStreamResponse(_request, resume)] = actions
  let response =
    Ok(response.new(401) |> response.set_body(new_reader([], Ok(Nil))))
  let assert system.Done(message) = resume(response)
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  assert state.Waiting == state.status
  assert Some("Provider rejected the API token (401).") == state.input_error
}

pub fn stream_finished_while_not_streaming_test() {
  let state = init()
  let #(s2, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert s2 == state
  assert [] == actions
}

pub fn eval_response_from_llm_test() {
  let id = "abc"
  let code = "!int_add(2, 3)"
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([chat.ToolResultMessage(id, "5", [])]) == state.status
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  assert "eyg.test" == request.host
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #("tool", "5") == message
}

pub fn eval_error_test() {
  let id = "abc"
  let code = "x"
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([chat.ToolResultMessage(id, "variable undefined: x", [])])
    == state.status
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  assert "eyg.test" == request.host
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #("tool", "variable undefined: x") == message
}

pub fn eval_aborted_test() {
  let id = "abc"
  let code = "perform Abort(\"STOP\")"
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([chat.ToolResultMessage(id, "STOP", [])]) == state.status
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  assert "eyg.test" == request.host
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #("tool", "STOP") == message
}

pub fn side_effect_test() {
  let id = "abc"
  let code = "perform Alert(\"Hello World\")"
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert state.Executing([call]) = state.status
  assert id == call.id
  let assert tools.Handling(..) = call.call
  let assert [system.Alert("Hello World", resume:)] = actions
  let assert system.Done(message) = resume()
  let #(state, actions) = state.update(state, message)
  assert state.Asking([chat.ToolResultMessage(id, "{}", [])]) == state.status
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  assert "eyg.test" == request.host
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #("tool", "{}") == message
}

pub fn synchronous_effect_resumes_the_program_test() {
  let status =
    chat_completion("")
    |> with_code("abc", "let _ = perform Random(1) 5")
    |> streaming
  let state = State(..init(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([chat.ToolResultMessage("abc", "5", [])]) == state.status
  let assert [system.FetchStreamResponse(..)] = actions
}

pub fn module_remains_in_context_for_second_tool_call_test() {
  let assert Ok(#(cid, _)) =
    v1.from_string(
      "bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy",
    )
  let ref = "#" <> v1.to_string(cid)

  let first_id = "first"
  let code = "!int_add(" <> ref <> ", 1)"
  let status = chat_completion("") |> with_code(first_id, code) |> streaming
  let state = State(..init(), status:)

  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert state.Executing([call]) = state.status

  let assert tools.Pending(dep:, ..) = call.call
  assert ir.Content(cid) == dep
  let assert [system.Fetch(request:, ..)] = actions
  assert "/modules/" <> v1.to_string(cid) == request.path

  let #(state, actions) =
    state.update(
      state,
      state.CacheMessage(cache.FetchModuleCompleted(cid, Ok(ir.integer(43)))),
    )
  assert state.Asking([chat.ToolResultMessage(first_id, "44", [])])
    == state.status
  // fetch completion
  let assert [_] = actions

  let second_id = "second"
  let code = "!int_add(" <> ref <> ", 10)"
  let status = chat_completion("") |> with_code(second_id, code) |> streaming
  let state = State(..state, status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))

  assert state.Asking([chat.ToolResultMessage(second_id, "53", [])])
    == state.status
  let assert [system.FetchStreamResponse(..)] = actions
}

pub fn module_returned_while_not_running_test() {
  let assert Ok(#(cid, _)) =
    v1.from_string(
      "bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy",
    )
  let state = init()
  let #(state, actions) =
    state.update(
      state,
      state.CacheMessage(cache.FetchModuleCompleted(cid, Ok(ir.integer(43)))),
    )
  assert state.Waiting == state.status
  assert [] == actions
}

pub fn module_lookup_failure_test() {
  let assert Ok(#(cid, _)) =
    v1.from_string(
      "bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy",
    )
  let id = "abc"
  let code = "!int_add(#" <> v1.to_string(cid) <> ", 1)"
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init(), status:)
  let #(state, _) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert [chat.AssistantMessage(tool_calls: [call], ..)] = state.history
  assert id == call.id

  let #(state, _actions) =
    state.update(
      state,
      state.CacheMessage(cache.FetchModuleCompleted(cid, Error("not fetched"))),
    )

  // asking is only the new messages
  let assert state.Asking(messages) = state.status
  let assert [chat.ToolResultMessage(tool_call_id:, text:, images:)] = messages
  assert id == tool_call_id
  assert "failed to fetch: #bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy"
    == text
  assert [] == images
}

pub fn invalid_module_is_reported_to_llm_test() {
  let assert Ok(#(cid, _)) =
    v1.from_string(
      "bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy",
    )
  let id = "abc"
  let code = "!int_add(#" <> v1.to_string(cid) <> ", 1)"
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init(), status:)
  let #(state, _) = state.update(state, state.LlmStreamFinished(Ok(Nil)))

  let #(state, actions) =
    state.update(
      state,
      state.CacheMessage(cache.FetchModuleCompleted(cid, Ok(ir.vacant()))),
    )

  assert state.Asking([chat.ToolResultMessage(id, "tried to run a todo", [])])
    == state.status
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #("tool", "tried to run a todo") == message
}

// package is pulled and then module
// module is pulled and then package
// packages failed to pull, shows retry button

pub fn unknown_package_pulls_cache_test() {
  let id = "abc"
  let code = "@foo"
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init() |> helpers.pulled([]), status:)

  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert [system.Fetch(request:, resume: _)] = actions
  assert "/packages/pull" == request.path
  let #(sig, key) = new_signatory()
  let number = int.random(1_000_000)
  let source = ir.integer(number)
  let cid = helpers.cid_from_tree(source)
  let entry = publisher.first(sig, key, "foo", cid)
  let archived = archive_entry(entry, 1)
  let message = state.CacheMessage(cache.PullPackagesCompleted(Ok([archived])))
  let #(state, actions) = state.update(state, message)
  // pulls again as got some values
  let assert [_pulls, system.Fetch(request:, resume: _)] = actions
  assert "/modules/" <> v1.to_string(cid) == request.path
  let message = state.CacheMessage(cache.FetchModuleCompleted(cid, Ok(source)))
  let #(state, actions) = state.update(state, message)
  assert state.Asking([chat.ToolResultMessage(id, int.to_string(number), [])])
    == state.status
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #("tool", int.to_string(number)) == message
}

pub fn unknown_version_pulls_cache_test() {
  let #(sig, key) = new_signatory()
  let number = int.random(1_000_000)
  let source = ir.integer(number)
  let cid = helpers.cid_from_tree(source)
  let entry = publisher.first(sig, key, "foo", cid)
  let archived = archive_entry(entry, 1)
  let release = ir.Release("foo", 1, cid)
  let id = "abc"
  let code = "@foo:2"
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init() |> helpers.pulled([release]), status:)
  assert cache.Pulled == state.cache.cursor_status

  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert [system.Fetch(request:, resume: _)] = actions
  assert "/packages/pull" == request.path
  let #(sig, key) = new_signatory()
  let number = int.random(1_000_000)
  let source = ir.integer(number)
  let cid = helpers.cid_from_tree(source)
  let entry = publisher.follow(sig, key, "foo", cid, archived)
  let archived = archive_entry(entry, 1)
  let message = state.CacheMessage(cache.PullPackagesCompleted(Ok([archived])))
  let #(state, actions) = state.update(state, message)
  // pulls again as got some values
  let assert [_pulls, system.Fetch(request:, resume: _)] = actions
  assert "/modules/" <> v1.to_string(cid) == request.path
  let message = state.CacheMessage(cache.FetchModuleCompleted(cid, Ok(source)))
  let #(state, actions) = state.update(state, message)
  assert state.Asking([chat.ToolResultMessage(id, int.to_string(number), [])])
    == state.status
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #("tool", int.to_string(number)) == message
}

pub fn incorrect_release_cache_test() {
  let #(sig, key) = new_signatory()
  let number = int.random(1_000_000)
  let source = ir.integer(number)
  let cid = helpers.cid_from_tree(source)
  let entry = publisher.first(sig, key, "foo", cid)
  let _archived = archive_entry(entry, 1)
  let release = ir.Release("foo", 1, cid)
  let id = "abc"
  let code = "@foo:1:" <> v1.to_string(dag_json.vacant_cid)
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init() |> helpers.pulled([release]), status:)
  assert cache.Pulled == state.cache.cursor_status

  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([
      chat.ToolResultMessage(
        id,
        "invalid hash for reference: @foo:1:baguqeerar6vyjqns54f63oywkgsjsnrcnuiixwgrik2iovsp7mdr6wplmsma",
        [],
      ),
    ])
    == state.status
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #(
      "tool",
      "invalid hash for reference: @foo:1:baguqeerar6vyjqns54f63oywkgsjsnrcnuiixwgrik2iovsp7mdr6wplmsma",
    )
    == message
}

/// returns entity (cid) and key (string)
fn new_signatory() {
  #(dag_json.vacant_cid, "key")
}

fn archive_entry(release: publisher.Entry, cursor: Int) {
  let substrate.Entry(sequence:, previous:, signatory:, key: _, content: _) =
    release
  let block = publisher.to_bytes(release)
  let assert Ok(payload) = block |> bit_array.to_string
  schema.ArchivedEntry(
    cursor:,
    cid: helpers.cid_from_block(block),
    payload:,
    entity: signatory,
    sequence:,
    previous:,
    type_: "release",
  )
}

pub fn invalid_source_code_test() {
  let id = "abc"
  let status = chat_completion("") |> with_code(id, "$") |> streaming
  let state = State(..init(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert state.Asking([
    chat.ToolResultMessage(tool_call_id:, text:, images:),
  ]) = state.status
  assert id == tool_call_id
  assert "invalid character '$' at position 0" == text
  assert [] == images
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  assert "eyg.test" == request.host
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  let assert #("tool", "invalid character '$' at position 0") = message
}

pub fn malformed_tool_arguments_test() {
  let id = "abc"
  let call =
    tool.Call(
      id:,
      function: tool.FunctionCall(
        name: "run",
        arguments: dict.from_list([#("not_code", utils.String("unused"))]),
      ),
    )
  let status = chat_completion("") |> with_call(call) |> streaming
  let state = State(..init(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert state.Asking([
    chat.ToolResultMessage(tool_call_id:, text:, images:),
  ]) = state.status
  assert id == tool_call_id
  assert string.contains(text, "code")
  assert [] == images
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  assert "eyg.test" == request.host
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  let assert #("tool", _) = message
}

fn streaming(completion) {
  state.Streaming(reader: new_reader([], Ok(Nil)), completion:, remaining: <<>>)
}

fn chat_completion(content) {
  chat.Completion(thinking: "", content:, tool_calls: [])
}

fn with_code(completion: chat.Completion(tool.Call), id, code) {
  let call = run_code(id, code)

  with_call(completion, call)
}

fn with_call(completion: chat.Completion(tool.Call), call) {
  let tool_calls = list.append(completion.tool_calls, [call])
  chat.Completion(..completion, tool_calls:)
}

fn run_code(id, code) {
  tool.Call(
    id:,
    function: tool.FunctionCall(
      name: "run",
      arguments: dict.from_list([
        #("code", utils.String(code)),
      ]),
    ),
  )
}

pub fn printed_output_is_returned_to_the_agent_test() {
  let code =
    "let _ = perform Print(\"first\") let _ = perform Print(\"second\") 5"
  let status = chat_completion("") |> with_code("abc", code) |> streaming
  let state = State(..init(), status:)
  let #(state, _actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([
      chat.ToolResultMessage("abc", "Output:\nfirstsecond\nResult:\n5", []),
    ])
    == state.status
}

pub fn printing_before_an_effect_suspends_test() {
  let code = "let _ = perform Print(\"before\") perform Alert(\"hi\")"
  let status = chat_completion("") |> with_code("abc", code) |> streaming
  let state = State(..init(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert [system.Alert("hi", resume:)] = actions
  let assert system.Done(message) = resume()
  let #(state, _actions) = state.update(state, message)
  assert state.Asking([
      chat.ToolResultMessage("abc", "Output:\nbefore\nResult:\n{}", []),
    ])
    == state.status
}

pub fn printing_before_a_module_suspends_test() {
  let assert Ok(#(cid, _)) =
    v1.from_string(
      "bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy",
    )
  let code =
    "let _ = perform Print(\"before\") !int_add(#"
    <> v1.to_string(cid)
    <> ", 1)"
  let status = chat_completion("") |> with_code("abc", code) |> streaming
  let state = State(..init(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert [system.Fetch(..)] = actions

  let #(state, _) =
    state.update(
      state,
      state.CacheMessage(cache.FetchModuleCompleted(cid, Ok(ir.integer(6)))),
    )
  assert state.Asking([
      chat.ToolResultMessage("abc", "Output:\nbefore\nResult:\n7", []),
    ])
    == state.status
}
