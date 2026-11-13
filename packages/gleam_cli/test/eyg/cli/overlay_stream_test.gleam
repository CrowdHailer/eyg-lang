import eyg/cli/helpers
import eyg/cli/overlay
import glasshouse/archive
import glasshouse/session
import glasshouse/store
import gleam/bit_array
import gleam/http/response
import gleam/list
import gleam/option.{Some}
import gleam/string
import loam/sandbox
import loam/source
import loam/system
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
