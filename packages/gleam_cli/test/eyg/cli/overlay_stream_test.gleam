import eyg/cli/helpers
import eyg/cli/internal/terminal
import eyg/cli/overlay
import glasshouse/archive
import glasshouse/context
import glasshouse/rerun
import glasshouse/session
import glasshouse/store
import gleam/bit_array
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import loam/sandbox
import loam/source
import loam/system
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/bedrock
import overlay/llm/provider/codex
import overlay/llm/sigv4
import overlay/policy
import touch_grass/harness/computer
import touch_grass/interface

fn prepared() {
  let code =
    "{llm: {provider: Ollama({origin: \"https://fixture.test\", api_key: None({})}), model: \"fixture\"}, policy: {now: (x) -> { Pass(x) }}, context: {}}"
  let rules = [#("Now", policy.PolicyField("now"))]
  let harness = computer.effects() |> interface.take(["Now"])
  let assert #(sandbox.Returned(#(Ok(session), state)), host) =
    overlay.setup(
      source.Code(code),
      helpers.config,
      harness,
      rules,
      helpers.state(),
    )
    |> sandbox.run(sandbox.sandbox() |> sandbox.with_now(100))
  #(session, state, host)
}

pub fn a_stopped_turn_does_not_request_another_completion_test() {
  let #(session, state, host) = prepared()
  let host =
    sandbox.save_and_return(host, response.new(200) |> response.set_body(<<>>))
  terminal.request_stop(session.interrupt)
  let trace = overlay.start_trace("stopped-before-fetch", session)
  let assert #(sandbox.Returned(#(Error(reason), _, trace)), host) =
    overlay.inner_loop(session, state, [], trace) |> sandbox.run(host)
  assert reason == overlay.stopped_message
  assert host.network_state == []
  assert trace.generations == 0
}

pub fn interrupted_stream_keeps_received_bytes_in_a_closed_archive_test() {
  let #(session, _, host) = prepared()
  let bytes = <<"{\"message\":{\"content\":\"Working\"}}\n">>
  let host =
    sandbox.save_and_return(host, response.new(200) |> response.set_body(bytes))
  let trace = overlay.start_trace("stopped-stream", session)
  let assert #(sandbox.Returned(#(Error(reason), trace)), host) =
    overlay.streamed_generation(session, [], trace, fn(text) {
      terminal.request_stop(session.interrupt)
      system.write_stdout(text)
    })
    |> sandbox.run(host)
  assert reason == overlay.stopped_message
  assert host.stdout |> list.reverse |> string.concat == "Working"
  let archive = overlay.to_archive(session, trace, 101)
  assert archive.missing(archive) == []
  let assert [generation] = session.generations(archive.session)
  assert generation.error == Some(overlay.stopped_message)
  let assert Some(cid) = generation.response
  assert store.get_binary(archive.store, cid) == Ok(bytes)
}

pub fn an_interrupt_after_a_tool_skips_later_calls_in_the_batch_test() {
  let #(session, state, host) = prepared()
  let session = overlay.Session(..session, persist: False)
  let bytes = <<
    "{\"message\":{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"function\":{\"name\":\"run\",\"arguments\":{\"code\":\"perform Now({})\"}}},{\"function\":{\"name\":\"run\",\"arguments\":{\"code\":\"perform Now({})\"}}}]},\"done\":true}",
  >>
  let host =
    sandbox.save_and_return(host, response.new(200) |> response.set_body(bytes))
  let trace = overlay.start_trace("stopped-tools", session)
  let trace =
    overlay.Trace(..trace, observe: fn(progress) {
      let archive = overlay.to_archive(session, progress, 101)
      case list.length(session.runs(archive.session)) > 1 {
        True -> terminal.request_stop(session.interrupt)
        False -> Nil
      }
    })
  let assert #(sandbox.Returned(#(Error(reason), _, trace)), _) =
    overlay.inner_loop(session, state, [], trace) |> sandbox.run(host)
  assert reason == overlay.stopped_message
  let archive = overlay.to_archive(session, trace, 101)
  assert archive.missing(archive) == []
  assert list.length(session.runs(archive.session)) == 2
  assert trace.generations == 1
}

pub fn streaming_keeps_unterminated_final_event_exact_bytes_and_usage_test() {
  let #(session, _, host) = prepared()
  let bytes = <<
    "{\"message\":{\"content\":\"Hello \"}}\n{\"message\":{\"content\":\"🌿\"},\"done\":true,\"prompt_eval_count\":40,\"eval_count\":8}",
  >>
  let response = response.new(200) |> response.set_body(bytes)
  let host = sandbox.save_and_return(host, response)
  let trace = overlay.start_trace("stream-check", session)
  let assert #(sandbox.Returned(#(Ok(completion), trace)), host) =
    overlay.streamed_generation(session, [], trace, system.write_stdout)
    |> sandbox.run(host)
  assert completion.content == "Hello 🌿"
  assert host.stdout |> list.reverse |> string.concat == "Hello 🌿"
  let archive = overlay.to_archive(session, trace, 101)
  assert archive.missing(archive) == []
  let assert [generation] = session.generations(archive.session)
  assert generation.usage == session.Usage(40, 8)
  let assert Some(cid) = generation.response
  assert store.get_binary(archive.store, cid) == Ok(bytes)
  let cid = generation.request
  let assert Ok(request) = store.get_binary(archive.store, cid)
  let assert Ok(request) = bit_array.to_string(request)
  assert request != ""
}

pub fn streamed_http_errors_keep_the_body_without_emitting_assistant_text_test() {
  let #(session, _, host) = prepared()
  let bytes = <<"{\"message\":{\"content\":\"Denied\"}}\n">>
  let reply = response.new(503) |> response.set_body(bytes)
  let host = sandbox.save_and_return(host, reply)
  let trace = overlay.start_trace("stream-error", session)
  let assert #(sandbox.Returned(#(Error(reason), trace)), host) =
    overlay.streamed_generation(session, [], trace, system.write_stdout)
    |> sandbox.run(host)
  assert string.starts_with(reason, "unexpected status: 503")
  assert host.stdout == []
  let archive = overlay.to_archive(session, trace, 101)
  let assert [generation] = session.generations(archive.session)
  assert generation.status == 503
  let assert Some(cid) = generation.response
  assert store.get_binary(archive.store, cid) == Ok(bytes)
}

fn bedrock_session() {
  let #(session, state, host) = prepared()
  let llm =
    provider.Llm(
      provider.Bedrock(bedrock.Config(
        "eu-west-1",
        sigv4.Credentials(
          "fixture-key",
          "fixture-secret",
          Some("fixture-token"),
        ),
      )),
      "anthropic.claude-sonnet:0",
    )
  #(overlay.Session(..session, llm:, persist: False), state, host)
}

pub fn bedrock_tool_round_trip_records_usage_and_replays_test() {
  let #(session, state, host) = bedrock_session()
  let host =
    sandbox.with_network(
      host,
      fn(request, requests) {
        assert request.path == "/model/anthropic.claude-sonnet%3A0/converse"
        let assert Ok(auth) = list.key_find(request.headers, "authorization")
        assert string.contains(auth, "/eu-west-1/bedrock/aws4_request")
        assert list.key_find(request.headers, "x-amz-security-token")
          == Ok("fixture-token")
        let assert Ok(messages) = context.from_request(request.body)
        let content = case requests {
          [] ->
            "{\"toolUse\":{\"toolUseId\":\"t1\",\"name\":\"run\",\"input\":{\"code\":\"!int_add(20, 22)\"}}}"
          _ -> {
            assert list.any(messages, fn(message) {
              case message {
                context.Tool("t1", text) -> string.contains(text, "42")
                _ -> False
              }
            })
            "{\"text\":\"Computed 42.\"}"
          }
        }
        let body =
          "{\"output\":{\"message\":{\"content\":["
          <> content
          <> "]}},\"usage\":{\"inputTokens\":7,\"outputTokens\":3}}"
        #(Ok(response.new(200) |> response.set_body(<<body:utf8>>)), [
          request,
          ..requests
        ])
      },
      [],
    )
  let trace = overlay.start_trace("bedrock-tools", session)
  let assert #(sandbox.Returned(#(Ok(_), _, trace)), host) =
    overlay.inner_loop(
      session,
      state,
      [chat.UserMessage("calculate", [])],
      trace,
    )
    |> sandbox.run(host)
  assert list.length(host.network_state) == 2
  let archive = overlay.to_archive(session, trace, 101)
  assert archive.missing(archive) == []
  let assert [first, second] = session.generations(archive.session)
  assert first.usage == session.Usage(7, 3)
    && second.usage == session.Usage(7, 3)
  assert first.error == None && second.error == None
  assert second.content == "Computed 42."
  assert list.all(rerun.session(archive.session, archive.store), fn(report) {
    report.problem == None
  })
}

pub fn bedrock_truncated_document_records_failure_test() {
  let #(session, _, host) = bedrock_session()
  let body = <<"{\"output\":">>
  let host =
    sandbox.save_and_return(host, response.new(200) |> response.set_body(body))
  let trace = overlay.start_trace("bedrock-truncated", session)
  let assert #(sandbox.Returned(#(Error(_), trace)), _) =
    overlay.streamed_generation(session, [], trace, system.write_stdout)
    |> sandbox.run(host)
  let archive = overlay.to_archive(session, trace, 101)
  let assert [generation] = session.generations(archive.session)
  let assert Some(_) = generation.error
  let assert Some(cid) = generation.response
  assert store.get_binary(archive.store, cid) == Ok(body)
}

fn codex_session() {
  let #(session, state, host) = prepared()
  let llm =
    provider.Llm(
      provider.Codex(codex.Config("fixture-token", "fixture-account")),
      "scripted-codex",
    )
  #(overlay.Session(..session, llm:, persist: False), state, host)
}

pub fn codex_tool_round_trip_records_usage_and_replays_test() {
  let #(session, state, host) = codex_session()
  let host =
    sandbox.with_network(
      host,
      fn(request, requests) {
        assert request.path == "/backend-api/codex/responses"
        assert request.host == "chatgpt.com"
        assert list.key_find(request.headers, "authorization")
          == Ok("Bearer fixture-token")
        assert list.key_find(request.headers, "chatgpt-account-id")
          == Ok("fixture-account")
        let assert Ok(messages) = context.from_request(request.body)
        let item = case requests {
          [] ->
            "{\"type\":\"function_call\",\"call_id\":\"t1\",\"name\":\"run\",\"arguments\":\"{\\\"code\\\":\\\"!int_add(20, 22)\\\"}\"}"
          _ -> {
            assert list.any(messages, fn(message) {
              case message {
                context.Tool("t1", text) -> string.contains(text, "42")
                _ -> False
              }
            })
            "{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Computed 42.\"}]}"
          }
        }
        let body =
          "data: {\"type\":\"response.output_item.done\",\"item\":"
          <> item
          <> "}\r\n\r\n"
          <> "data: {\"type\":\"response.completed\",\"response\":{\"output\":["
          <> item
          <> "],\"usage\":{\"input_tokens\":7,\"output_tokens\":3}}}\r\n\r\n"
        #(Ok(response.new(200) |> response.set_body(<<body:utf8>>)), [
          request,
          ..requests
        ])
      },
      [],
    )
  let trace = overlay.start_trace("codex-tools", session)
  let assert #(sandbox.Returned(#(Ok(_), _, trace)), host) =
    overlay.inner_loop(
      session,
      state,
      [chat.UserMessage("calculate", [])],
      trace,
    )
    |> sandbox.run(host)
  assert list.length(host.network_state) == 2
  let saved = overlay.to_archive(session, trace, 101)
  assert archive.missing(saved) == []
  let assert Some(agent) = saved.session.agent
  assert agent.provider == "openai-codex"
  let assert [first, second] = session.generations(saved.session)
  assert first.usage == session.Usage(7, 3)
    && second.usage == session.Usage(7, 3)
  assert second.content == "Computed 42."
  assert list.all(rerun.session(saved.session, saved.store), fn(report) {
    report.problem == None
  })
}

pub fn codex_stream_failure_is_recorded_without_assistant_text_test() {
  let #(session, _, host) = codex_session()
  let body = <<
    "data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"message\":\"usage limit reached\"}}}\n\n",
  >>
  let host =
    sandbox.save_and_return(host, response.new(200) |> response.set_body(body))
  let trace = overlay.start_trace("codex-failed", session)
  let assert #(sandbox.Returned(#(Error(reason), trace)), host) =
    overlay.streamed_generation(session, [], trace, system.write_stdout)
    |> sandbox.run(host)
  assert reason == "usage limit reached"
  assert host.stdout |> list.reverse |> string.concat == ""
  let saved = overlay.to_archive(session, trace, 101)
  let assert [generation] = session.generations(saved.session)
  assert generation.error == Some("usage limit reached")
  let assert Some(cid) = generation.response
  assert store.get_binary(saved.store, cid) == Ok(body)
}
