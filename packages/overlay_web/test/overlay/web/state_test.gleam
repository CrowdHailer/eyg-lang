import eyg/hub/cache
import eyg/hub/publisher
import eyg/interpreter/value
import eyg/ir/dag_json
import eyg/ir/tree as ir
import glasshouse/journal
import glasshouse/session
import gleam/bit_array
import gleam/dict
import gleam/fetch
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import oas/generator/utils
import ogre/origin
import overlay/helpers.{init, init_default, new_reader, submit_first_prompt}
import overlay/llm/chat
import overlay/llm/tool
import overlay/web/artifact
import overlay/web/context
import overlay/web/provider_setup
import overlay/web/state.{State}
import overlay/web/tools
import overlay/web/workspace
import pal/system
import untethered/ledger/schema
import untethered/substrate

pub fn init_loads_provider_settings_test() {
  let config =
    state.Config(origin: origin.https("eyg.test"), context: context.Default)
  let #(state, actions) = state.init(config)
  let assert [
    system.GetSessionStorageItem("overlay.llm.provider", _),
    _,
    system.GetSessionStorageItem("overlay.history", _),
    system.GetSessionStorageItem("overlay.artifacts", _),
  ] = actions
  assert True == state.provider_setup.restoring
}

pub fn provider_setup_selects_new_llm_test() {
  let config =
    state.Config(origin: origin.https("eyg.test"), context: context.Default)
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
  let config =
    state.Config(origin: origin.https("eyg.test"), context: context.Default)
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
  // The finished conversation is saved for the tab
  let assert [system.SetSessionStorageItem("overlay.history", _, _)] = actions
}

pub fn cant_submit_if_busy_test() {
  let state =
    State(
      ..init_default(),
      status: state.Asking([chat.UserMessage("Hi there", [])]),
      input: "something",
    )
  let #(state, actions) = state.update(state, state.UserSubmittedPrompt)
  let assert Some(_) = state.input_error
  assert [] == actions
}

pub fn started_streaming_while_not_asking_test() {
  let state = init_default()
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
  let state = init_default()
  let #(s2, actions) =
    state.update(state, state.LlmStreamedCompletion([], <<>>, <<>>))
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
  let assert system.ReadChunk(_, read) = resume(response)
  let assert system.ReadChunk(_, read) =
    read(Ok(Some(<<"{\"error\":\"unauthorized\"}":utf8>>)))
  let assert system.Done(message) = read(Ok(None))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  assert state.Waiting == state.status
  assert Some(
      "Provider rejected the API token (401). {\"error\":\"unauthorized\"}",
    )
    == state.input_error
  // The prompt can be sent again
  assert "hello" == state.input
}

pub fn stream_finished_while_not_streaming_test() {
  let state = init_default()
  let #(s2, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert s2 == state
  assert [] == actions
}

pub fn eval_response_from_llm_test() {
  let id = "abc"
  let code = "!int_add(2, 3)"
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init_default(), status:)
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
  let state = State(..init_default(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([chat.ToolResultMessage(id, "missing variable 'x'", [])])
    == state.status
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  assert "eyg.test" == request.host
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #("tool", "missing variable 'x'") == message
}

pub fn eval_aborted_test() {
  let id = "abc"
  let code = "perform Abort(\"STOP\")"
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init_default(), status:)
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
  let state = State(..init_default(), status:)
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
  let state = State(..init_default(), status:)
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
  let state = State(..init_default(), status:)

  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert state.Executing([call]) = state.status

  let assert tools.Fetching(cids:, ..) = call.call
  assert [cid] == cids
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
  let state = init_default()
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
  let state = State(..init_default(), status:)
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
  assert "missing reference #bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy"
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
  let state = State(..init_default(), status:)
  let #(state, _) = state.update(state, state.LlmStreamFinished(Ok(Nil)))

  let #(state, actions) =
    state.update(
      state,
      state.CacheMessage(cache.FetchModuleCompleted(cid, Ok(ir.vacant()))),
    )

  assert state.Asking([
      chat.ToolResultMessage(
        id,
        "missing reference #bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy",
        [],
      ),
    ])
    == state.status
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #(
      "tool",
      "missing reference #bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy",
    )
    == message
}

// package is pulled and then module
// module is pulled and then package
// packages failed to pull, shows retry button

pub fn unknown_package_pulls_cache_test() {
  let id = "abc"
  let code = "@foo"
  let status = chat_completion("") |> with_code(id, code) |> streaming
  let state = State(..init_default() |> helpers.pulled([]), status:)

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
  let assert [system.Fetch(request:, resume: _)] = actions
  assert "/packages/pull" == request.path
  let message = state.CacheMessage(cache.PullPackagesCompleted(Ok([])))
  let #(state, actions) = state.update(state, message)

  let assert [system.Fetch(request:, resume: _)] = actions
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
  let state = State(..init_default() |> helpers.pulled([release]), status:)
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
  let assert [system.Fetch(request:, resume: _)] = actions
  assert "/packages/pull" == request.path
  let message = state.CacheMessage(cache.PullPackagesCompleted(Ok([])))
  let #(state, actions) = state.update(state, message)

  let assert [system.Fetch(request:, resume: _)] = actions
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
  let state = State(..init_default(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert state.Asking([
    chat.ToolResultMessage(tool_call_id:, text:, images:),
  ]) = state.status
  assert id == tool_call_id
  let expected =
    "error: invalid character '$' at position 0\nhint: remove or replace this character — EYG does not use it\n\n 1 | $\n     ^"
  assert expected == text
  assert [] == images
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  assert "eyg.test" == request.host
  let assert Ok([_system, _agent_message, message]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert #("tool", expected) == message
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
  let state = State(..init_default(), status:)
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
  let state = State(..init_default(), status:)
  let #(state, _actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([
      chat.ToolResultMessage("abc", "Output:\nfirstsecond\nResult:\n5", []),
    ])
    == state.status
}

pub fn printing_before_an_effect_suspends_test() {
  let code = "let _ = perform Print(\"before\") perform Alert(\"hi\")"
  let status = chat_completion("") |> with_code("abc", code) |> streaming
  let state = State(..init_default(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert [system.Alert("hi", resume:)] = actions
  let assert system.Done(message) = resume()
  let #(state, _actions) = state.update(state, message)
  assert state.Asking([
      chat.ToolResultMessage("abc", "Output:\nbefore\nResult:\n{}", []),
    ])
    == state.status
}

pub fn incorrect_release_cache_test() {
  let source = ir.integer(int.random(1_000_000))
  let cid = helpers.cid_from_tree(source)
  let release = ir.Release("foo", 1, cid)
  let code = "@foo:1:" <> v1.to_string(dag_json.vacant_cid)
  let status = chat_completion("") |> with_code("abc", code) |> streaming
  let state = State(..init_default() |> helpers.pulled([release]), status:)
  assert cache.Pulled == state.cache.cursor_status

  let #(state, _actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))

  assert state.Asking([
      chat.ToolResultMessage(
        "abc",
        "missing reference @foo:1:baguqeerar6vyjqns54f63oywkgsjsnrcnuiixwgrik2iovsp7mdr6wplmsma",
        [],
      ),
    ])
    == state.status
}

pub fn default_context_is_in_scope_test() {
  let code = "context.readme"
  let status = chat_completion("") |> with_code("abc", code) |> streaming
  let state = State(..init_default() |> helpers.pulled([]), status:)
  assert cache.Pulled == state.cache.cursor_status

  let #(state, _actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))

  let assert state.Asking([chat.ToolResultMessage("abc", response, [])]) =
    state.status
  assert string.contains(response, "overlay agent")
}

pub fn reference_context_test() {
  let source = ir.record([#("readme", ir.string("hi"))])
  let cid = helpers.cid_from_tree(source)
  let config =
    state.Config(
      origin: origin.https("eyg.test"),
      context: context.Reference(cid),
    )
  let #(state, actions) = state.init(config)
  assert context.Fetching([cid], ir.Content(cid)) == state.context
  let assert [
    _settings,
    _pull,
    system.Fetch(request:, resume: _),
    _history,
    _artifacts,
  ] = actions
  assert "/modules/" <> v1.to_string(cid) == request.path

  let message = state.CacheMessage(cache.FetchModuleCompleted(cid, Ok(source)))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  assert "hi" == context.readme(state.context)
}

pub fn cant_submit_while_context_loading_test() {
  let #(state, _actions) = init(context.Package("foo", None))
  let #(state, actions) = state.update(state, state.UserUpdatedInput("hello"))
  assert [] == actions

  let #(state, actions) = state.update(state, state.UserSubmittedPrompt)
  assert [] == actions
  assert Some("Context is still loading") == state.input_error
  assert state.Waiting == state.status
}

pub fn unknown_package_context_test() {
  let #(state, _actions) = init(context.Package("foo", None))
  assert context.Pulling(ir.Package("foo")) == state.context

  let message = state.CacheMessage(cache.PullPackagesCompleted(Ok([])))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  assert context.Errored("missing reference @foo") == state.context
  // The session carries on with the default context
  assert context.default_readme == context.readme(state.context)
}

pub fn package_context_test() {
  let context = context.Package("foo", Some(1))
  let #(state, actions) = init(context)
  assert context.Pulling(ir.Version("foo", 1)) == state.context
  // The test init always checks an action for getting LLM info and a pull
  assert [] == actions
  let #(sig, key) = new_signatory()
  let source = ir.record([#("readme", ir.string("hi"))])
  let cid = helpers.cid_from_tree(source)
  let entry = publisher.first(sig, key, "foo", cid)
  let archived = archive_entry(entry, 1)
  let message = state.CacheMessage(cache.PullPackagesCompleted(Ok([archived])))
  let #(state, actions) = state.update(state, message)
  // pulls again as got some values
  let assert [system.Fetch(request:, resume: _)] = actions
  assert "/packages/pull" == request.path
  let message = state.CacheMessage(cache.PullPackagesCompleted(Ok([])))
  let #(state, actions) = state.update(state, message)
  let assert context.Fetching(..) = state.context

  let assert [system.Fetch(request:, resume: _)] = actions
  assert "/modules/" <> v1.to_string(cid) == request.path
  let message = state.CacheMessage(cache.FetchModuleCompleted(cid, Ok(source)))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  let assert context.Loaded(_) = state.context
  assert "hi" == context.readme(state.context)

  // The loaded module, and not the default, is in scope for the agent
  let status =
    chat_completion("") |> with_code("abc", "context.readme") |> streaming
  let #(state, _actions) =
    state.update(State(..state, status:), state.LlmStreamFinished(Ok(Nil)))
  let assert state.Asking([chat.ToolResultMessage("abc", response, [])]) =
    state.status
  assert "hi" == response
}

pub fn service_effects_are_not_offered_test() {
  let assert Error(_) =
    list.find(tools.effects(), fn(effect) { effect.name == "GitHub" })
  let assert Ok(_) =
    list.find(tools.effects(), fn(effect) { effect.name == "Fetch" })
}

pub fn rejected_token_is_shown_in_settings_test() {
  let #(state, actions) = submit_first_prompt("hello")
  let assert [system.FetchStreamResponse(_request, resume)] = actions
  let response =
    Ok(response.new(401) |> response.set_body(new_reader([], Ok(Nil))))
  let assert system.ReadChunk(_, read) = resume(response)
  let assert system.Done(message) = read(Ok(None))
  let #(state, _actions) = state.update(state, message)
  let assert Some(_) = state.provider_setup.error
}

pub fn stop_while_executing_test() {
  let status =
    chat_completion("")
    |> with_code("abc", "perform Alert(\"Hello World\")")
    |> streaming
  let state = State(..init_default(), status:)
  let #(state, _actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert state.Executing(_) = state.status
  let #(state, actions) = state.update(state, state.UserClickedStop)
  let assert [system.SetSessionStorageItem("overlay.history", _, _)] = actions
  assert state.Waiting == state.status
  let assert [chat.ToolResultMessage("abc", "stopped by the user", []), ..] =
    state.history
}

pub fn step_limit_test() {
  let status =
    chat_completion("")
    |> with_code("abc", "5")
    |> streaming
  let state = State(..init_default(), status:, steps: state.max_steps)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert state.Waiting == state.status
  let assert [] =
    list.filter(actions, fn(action) {
      case action {
        system.FetchStreamResponse(..) -> True
        _ -> False
      }
    })
  let assert Some(
    "Stopped after 25 rounds of tool calls, send a message to continue.",
  ) = state.input_error
}

/// A policy that passes every gated browser effect, except for the overridden fields.
fn with_policy(overrides) {
  let fields =
    [
      "alert", "copy", "download", "fetch", "now", "paste", "print", "prompt",
      "visit", "artifact", "show", "puppet",
    ]
    |> list.map(fn(field) {
      let gate =
        list.key_find(overrides, field)
        |> result.unwrap("(lift) -> { Pass(lift) }")
      field <> ": " <> gate
    })
  let code = "{" <> string.join(fields, ", ") <> "}"
  let state = init_default()
  let #(state, _) = state.update(state, state.UserUpdatedPolicy(code))
  let #(state, _) = state.update(state, state.UserAppliedPolicy)
  assert None == state.policy_error
  state
}

pub fn policy_requires_every_gated_effect_test() {
  let state = init_default()
  let #(state, _) = state.update(state, state.UserUpdatedPolicy("{}"))
  let #(state, _) = state.update(state, state.UserAppliedPolicy)
  let assert Some(reason) = state.policy_error
  assert string.contains(reason, "missing row 'alert'")
  assert None == state.policy
}

pub fn policy_mocks_effect_test() {
  let state = with_policy([#("now", "(_) -> { Mock(7) }")])
  let status =
    chat_completion("") |> with_code("abc", "perform Now({})") |> streaming
  let #(state, _) =
    state.update(State(..state, status:), state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([chat.ToolResultMessage("abc", "7", [])]) == state.status
  let assert [session.ToolResult(..), session.Execution(run), ..] =
    state.trace.events
  let assert [entry] = run.journal
  assert entry.answer == journal.Mocked
}

pub fn modified_policy_requests_are_recorded_as_hashes_test() {
  let state = with_policy([#("print", "(_) -> { Pass(\"replaced\") }")])
  let status =
    chat_completion("")
    |> with_code("abc", "perform Print(\"before\")")
    |> streaming
  let #(state, _) =
    state.update(State(..state, status:), state.LlmStreamFinished(Ok(Nil)))
  let assert [session.ToolResult(text:, ..), session.Execution(run), ..] =
    state.trace.events
  assert string.contains(text, "replaced")
  let assert [entry] = run.journal
  let assert journal.Altered(sent) = entry.answer
  assert string.starts_with(sent, "baguqeera")
}

pub fn invalid_policy_is_reported_test() {
  let state = init_default()
  let #(state, _) =
    state.update(state, state.UserUpdatedPolicy("{alert: (_) -> { Mock(1) }}"))
  let #(state, _) = state.update(state, state.UserAppliedPolicy)
  let assert Some(_) = state.policy_error
  assert None == state.policy
}

pub fn history_is_restored_test() {
  let history = [
    chat.AssistantMessage("", "Hi", []),
    chat.UserMessage("hello", []),
  ]
  let stored = chat.history_to_json(history) |> json.to_string
  let #(state, _) =
    state.update(init_default(), state.HistoryLoaded(Ok(Some(stored))))
  assert history == state.history
  let #(state, actions) = state.update(state, state.UserClickedNewChat)
  assert [] == state.history
  let assert [system.SetSessionStorageItem("overlay.history", "[]", _)] =
    actions
}

pub fn export_downloads_the_chat_test() {
  let history = [
    chat.AssistantMessage("", "Hi", []),
    chat.UserMessage("hello", []),
  ]
  let state = State(..init_default(), history:)
  let assert [system.Download(input, _)] =
    state.update(state, state.UserClickedExport).1
  assert string.starts_with(input.name, "overlay-session-")
  let assert Ok(content) = bit_array.to_string(input.content)
  assert string.contains(content, "\"text\":\"hello\"")
}

pub fn artifact_state_survives_agent_turns_and_closing_panels_test() {
  let save =
    "perform Artifact({name:\"map\",bundle:[{path:\"index.html\",media_type:\"text/html\",content:!string_to_binary(\"map\")}]})"
  let status = chat_completion("") |> with_code("one", save) |> streaming
  let #(s, _) =
    state.update(
      State(..init_default(), status:),
      state.LlmStreamFinished(Ok(Nil)),
    )
  let status = chat_completion("") |> with_code("two", save) |> streaming
  let #(s, _) =
    state.update(State(..s, status:), state.LlmStreamFinished(Ok(Nil)))
  assert 2 == list.length(artifact.history(s.artifacts, "map"))
  let status =
    chat_completion("")
    |> with_code(
      "show",
      "perform Show({item:Artifact(\"map\"),origin:{x:0,y:0},size:{x:1000,y:1000}})",
    )
    |> streaming
  let #(s, _) =
    state.update(State(..s, status:), state.LlmStreamFinished(Ok(Nil)))
  assert 1 == list.length(s.artifacts.panels)
  let #(s, _) =
    state.update(s, state.UserClosedArtifact(artifact.Artifact("map")))
  assert [] == s.artifacts.panels
  assert 2 == list.length(artifact.history(s.artifacts, "map"))
}

pub fn sharing_moves_one_version_to_the_hub_test() {
  let save =
    "perform Artifact({name:\"map\",bundle:[{path:\"index.html\",media_type:\"text/html\",content:!string_to_binary(\"map\")}]})"
  let status = chat_completion("") |> with_code("one", save) |> streaming
  let #(s, _) =
    state.update(
      State(..init_default(), status:),
      state.LlmStreamFinished(Ok(Nil)),
    )
  let status = chat_completion("") |> with_code("two", save) |> streaming
  let #(s, _) =
    state.update(State(..s, status:), state.LlmStreamFinished(Ok(Nil)))

  // Nothing leaves the session until a person clicks share.
  assert dict.new() == s.artifacts.shares
  let #(s, actions) =
    state.update(s, state.UserClickedShare(artifact.Artifact("map")))
  assert Ok(artifact.Sharing) == dict.get(s.artifacts.shares, #("map", 2))
  let assert [system.Fetch(request:, resume:)] = actions
  assert "/artifacts" == request.path
  let assert Ok(body) = bit_array.to_string(request.body)
  assert string.contains(body, "\"name\":\"map\"")

  let response =
    response.new(201)
    |> response.set_body(<<"{\"id\":\"a-uuid\",\"secret\":\"s\"}">>)
  let assert system.Done(message) = resume(Ok(response))
  let #(s, _) = state.update(s, message)
  assert Ok(artifact.Shared("a-uuid", "s"))
    == dict.get(s.artifacts.shares, #("map", 2))

  let #(s, actions) =
    state.update(s, state.UserClickedShare(artifact.Revision("map", 1)))
  let assert [system.Fetch(resume:, ..)] = actions
  let response =
    response.new(422)
    |> response.set_body(<<"{\"reason\":\"too big\"}">>)
  let assert system.Done(message) = resume(Ok(response))
  let #(s, _) = state.update(s, message)
  assert Ok(artifact.ShareFailed("too big"))
    == dict.get(s.artifacts.shares, #("map", 1))
}

pub fn sharing_a_later_version_names_the_previous_share_test() {
  let save =
    "perform Artifact({name:\"map\",bundle:[{path:\"index.html\",media_type:\"text/html\",content:!string_to_binary(\"map\")}]})"
  let status = chat_completion("") |> with_code("one", save) |> streaming
  let #(s, _) =
    state.update(
      State(..init_default(), status:),
      state.LlmStreamFinished(Ok(Nil)),
    )
  let status = chat_completion("") |> with_code("two", save) |> streaming
  let #(s, _) =
    state.update(State(..s, status:), state.LlmStreamFinished(Ok(Nil)))

  let #(s, actions) =
    state.update(s, state.UserClickedShare(artifact.Revision("map", 1)))
  let assert [system.Fetch(request:, resume:)] = actions
  let assert Ok(body) = bit_array.to_string(request.body)
  assert !string.contains(body, "previous")
  let response =
    response.new(201)
    |> response.set_body(<<"{\"id\":\"first\",\"secret\":\"s1\"}">>)
  let assert system.Done(message) = resume(Ok(response))
  let #(s, _) = state.update(s, message)

  let #(_s, actions) =
    state.update(s, state.UserClickedShare(artifact.Artifact("map")))
  let assert [system.Fetch(request:, ..)] = actions
  let assert Ok(body) = bit_array.to_string(request.body)
  assert string.contains(
    body,
    "\"previous\":{\"id\":\"first\",\"secret\":\"s1\"}",
  )
}

fn with_policy_in(state: state.State, overrides) {
  let browser = [
    "alert", "artifact", "copy", "download", "fetch", "now", "paste", "print",
    "prompt", "puppet", "show", "visit",
  ]
  let files = [
    "append_file", "delete_file", "make_directory", "read_directory",
    "read_file", "write_file",
  ]
  let fields =
    case state.workspace {
      Some(_) -> list.append(browser, files)
      None -> browser
    }
    |> list.map(fn(field) {
      let gate =
        list.key_find(overrides, field)
        |> result.unwrap("(lift) -> { Pass(lift) }")
      field <> ": " <> gate
    })
  let code = "{" <> string.join(fields, ", ") <> "}"
  let #(state, _) = state.update(state, state.UserUpdatedPolicy(code))
  let #(state, _) = state.update(state, state.UserAppliedPolicy)
  assert None == state.policy_error
  state
}

pub fn artifacts_are_checked_by_policy_test() {
  let state = with_policy([#("artifact", "(_) -> { Mock(Error(\"denied\")) }")])
  let status =
    chat_completion("")
    |> with_code(
      "artifact",
      "perform Artifact({name: \"denied\", bundle: [{path: \"index.html\", media_type: \"text/html\", content: !string_to_binary(\"hello\")}]})",
    )
    |> streaming
  let #(state, _) =
    state.update(State(..state, status:), state.LlmStreamFinished(Ok(Nil)))
  let assert state.Asking([chat.ToolResultMessage("artifact", reason, [])]) =
    state.status
  assert string.contains(reason, "denied")
  let assert Error(_) = artifact.revision(state.artifacts, "denied", 1)
}

pub fn finished_runs_keep_computed_values_test() {
  let status =
    chat_completion("")
    |> with_code("first", "!int_add(2, 3)")
    |> with_code("second", "perform Alert(\"Hello World\")")
    |> streaming
  let state = State(..init_default(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  // Nothing is kept until every call of the completion has finished.
  assert [] == state.runs
  let assert [system.Alert("Hello World", resume:)] = actions
  let assert system.Done(message) = resume()
  let #(state, _actions) = state.update(state, message)
  let assert [second, first] = state.runs
  assert "first" == first.id
  assert tools.Successful(value.Integer(5)) == first.call
  assert "second" == second.id
  assert tools.Successful(value.unit()) == second.call
}

pub fn workspace_sessions_can_change_files_test() {
  let code =
    "let _ = perform WriteFile({path: \"notes.md\", contents: !string_to_binary(\"hi\")})
match perform ReadFile({path: \"notes.md\", offset: 0, limit: 10}) {
  Ok(bytes) -> { !string_from_binary(bytes) }
  Error(reason) -> { Error({}) }
}"
  let status = chat_completion("") |> with_code("abc", code) |> streaming
  let files = workspace.new()
  let state = State(..init_default(), status:, workspace: Some(files))
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  assert state.Asking([chat.ToolResultMessage("abc", "Ok(\"hi\")", [])])
    == state.status
  let assert Some(files) = state.workspace
  assert [#("notes.md", <<"hi">>)] == workspace.files(files)

  // The system prompt only offers file effects to sessions with a workspace.
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  let assert Ok([#("system", prompt), ..]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert string.contains(prompt, "ReadFile")
}

pub fn file_effects_need_a_workspace_test() {
  let code = "perform ReadFile({path: \"notes.md\", offset: 0, limit: 10})"
  let status = chat_completion("") |> with_code("abc", code) |> streaming
  let state = State(..init_default(), status:)
  let #(state, actions) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert state.Asking([chat.ToolResultMessage("abc", reason, [])]) =
    state.status
  assert string.contains(reason, "ReadFile")
  assert None == state.workspace
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  let assert Ok([#("system", prompt), ..]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert !string.contains(prompt, "ReadFile")
}

pub fn system_prompt_lists_effect_types_test() {
  let #(_state, actions) = submit_first_prompt("hello")
  let assert [system.FetchStreamResponse(request:, resume: _)] = actions
  let assert Ok([#("system", prompt), ..]) =
    json.parse_bits(request.body, helpers.ollama_messages_decoder())
  assert string.contains(prompt, "\nAlert(↑String ↓{})\n")
}

pub fn workspace_writes_are_checked_by_policy_test() {
  let state =
    with_policy_in(State(..init_default(), workspace: Some(workspace.new())), [
      #("write_file", "(_) -> { Mock(Error(\"denied\")) }"),
    ])
  let status =
    chat_completion("")
    |> with_code(
      "write",
      "perform WriteFile({path: \"notes.md\", contents: !string_to_binary(\"hi\")})",
    )
    |> streaming
  let state = State(..state, status:)
  let #(state, _) = state.update(state, state.LlmStreamFinished(Ok(Nil)))
  let assert Some(files) = state.workspace
  assert [] == workspace.files(files)
  let assert state.Asking([chat.ToolResultMessage("write", reason, [])]) =
    state.status
  assert string.contains(reason, "denied")
}
