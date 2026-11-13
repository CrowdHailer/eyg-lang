import eyg/interpreter/value as v
import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import javascript/mutable_reference
import overlay/eval/agent.{Reply}
import overlay/eval/environment
import overlay/eval/fixture/hub
import overlay/eval/fixture/site
import overlay/eval/model
import overlay/eval/module
import overlay/eval/session
import overlay/eval/transcript

fn config(agent, prompts) {
  let assert Ok(site) = site.load("test/fixtures/guides")
  let assert Ok(hub) =
    hub.publish_directory(hub.new(), "test/fixtures/packages")
  session.Config(
    environment: environment.Environment(..environment.empty(), site:, hub:),
    context: session.NoContext,
    model: model.Scripted(agent),
    workspace: None,
    prompts:,
    max_model_calls: 10,
  )
}

pub fn a_computed_value_is_kept_test() {
  let agent =
    agent.scripted([
      [Reply("", ["!int_add(2, 3)"]), Reply("The answer is 5.", [])],
    ])
  use transcript <- promise.map(
    session.run(config(agent, ["What is two plus three?"])),
  )
  assert transcript.Finished == transcript.stop
  assert 2 == transcript.model_calls
  let assert [turn] = transcript.turns
  assert "What is two plus three?" == turn.prompt
  assert "The answer is 5." == transcript.reply(turn)
  let assert [run] = transcript.runs(transcript)
  assert "!int_add(2, 3)" == run.code
  assert transcript.Computed(v.Integer(5)) == run.outcome
}

pub fn prompts_are_sent_in_turn_test() {
  let agent =
    agent.scripted([
      [Reply("one", [])],
      [Reply("", ["\"second\""]), Reply("two", [])],
    ])
  use transcript <- promise.map(session.run(config(agent, ["first", "second"])))
  assert ["one", "two"] == list.map(transcript.turns, transcript.reply)
  assert 3 == transcript.model_calls
}

pub fn the_context_is_loaded_from_the_hub_test() {
  let assert Ok(loaded) =
    module.load("test/fixtures/packages/greeting/index.eyg")
  let agent =
    agent.scripted([
      [Reply("", ["context.hello(\"Ada\")"]), Reply("Hello, Ada", [])],
    ])
  let config =
    session.Config(
      ..config(agent, ["Greet Ada"]),
      context: session.Module(loaded),
    )
  use transcript <- promise.map(session.run(config))
  let assert [run] = transcript.runs(transcript)
  assert transcript.Computed(v.String("Hello, Ada")) == run.outcome
}

pub fn packages_are_pulled_from_the_hub_test() {
  let agent = agent.scripted([[Reply("", ["@numbers"]), Reply("Five", [])]])
  use transcript <- promise.map(session.run(config(agent, ["numbers"])))
  let assert [run] = transcript.runs(transcript)
  assert transcript.Computed(v.Integer(5)) == run.outcome
}

pub fn guides_are_fetched_from_the_site_test() {
  let code =
    "match perform Fetch({method: GET({}), scheme: HTTPS({}), host: \"eyg.run\", port: None({}), path: \"/guides/eyg-syntax-guide.md\", query: None({}), headers: [], body: !string_to_binary(\"\")}) {
  Ok({status, body}) -> { status }
  Error(reason) -> { 0 }
}"
  let agent = agent.scripted([[Reply("", [code]), Reply("Read it", [])]])
  use transcript <- promise.map(session.run(config(agent, ["syntax?"])))
  let assert [run] = transcript.runs(transcript)
  assert transcript.Computed(v.Integer(200)) == run.outcome
  assert [
      transcript.Fetch(
        transcript.Program,
        http.Get,
        "https://eyg.run/guides/eyg-syntax-guide.md",
        Ok(200),
      ),
    ]
    == list.filter(transcript.effects, fn(effect) {
      case effect {
        transcript.Fetch(url:, ..) -> string.contains(url, "/guides/")
        _ -> False
      }
    })
}

pub fn the_network_is_refused_offline_test() {
  let code =
    "match perform Fetch({method: GET({}), scheme: HTTPS({}), host: \"example.com\", port: None({}), path: \"/\", query: None({}), headers: [], body: !string_to_binary(\"\")}) {
  Ok(_) -> { \"reached\" }
  Error(reason) -> { reason }
}"
  let agent = agent.scripted([[Reply("", [code]), Reply("", [])]])
  use transcript <- promise.map(session.run(config(agent, ["fetch"])))
  let assert [run] = transcript.runs(transcript)
  let assert transcript.Computed(v.String(reason)) = run.outcome
  assert string.contains(reason, "no network access to example.com/")
  let assert [transcript.Fetch(status: Error(_), ..)] =
    list.filter(transcript.effects, fn(effect) {
      case effect {
        transcript.Fetch(by: transcript.Program, ..) -> True
        _ -> False
      }
    })
}

pub fn workspace_files_are_kept_test() {
  let code =
    "perform WriteFile({path: \"notes/today.md\", contents: !string_to_binary(\"learnt\")})"
  let agent = agent.scripted([[Reply("", [code]), Reply("Noted", [])]])
  let config =
    session.Config(
      ..config(agent, ["take a note"]),
      workspace: Some([#("notes/.keep", <<>>)]),
    )
  use transcript <- promise.map(session.run(config))
  let assert [run] = transcript.runs(transcript)
  assert transcript.Computed(v.ok(v.unit())) == run.outcome
  assert Some([#("notes/.keep", <<>>), #("notes/today.md", <<"learnt">>)])
    == transcript.workspace
}

pub fn sessions_stop_at_the_model_call_limit_test() {
  let busy = fn(_conversation) { Reply("", ["1"]) }
  let config = session.Config(..config(busy, ["loop"]), max_model_calls: 3)
  use transcript <- promise.map(session.run(config))
  assert transcript.ModelCallLimit(3) == transcript.stop
  assert 3 == transcript.model_calls
}

pub fn a_context_that_fails_to_load_stops_the_session_test() {
  let assert Ok(loaded) = module.from_source("!not_a_builtin(1)", ".")
  let agent = agent.scripted([[Reply("never", [])]])
  let config =
    session.Config(..config(agent, ["hi"]), context: session.Module(loaded))
  use transcript <- promise.map(session.run(config))
  let assert transcript.ContextFailed(_) = transcript.stop
  assert 0 == transcript.model_calls
}

pub fn module_loading_is_attributed_to_the_cache_test() {
  let agent = agent.scripted([[Reply("", ["@numbers"]), Reply("Five", [])]])
  use transcript <- promise.map(session.run(config(agent, ["numbers"])))
  let assert [_, ..] = transcript.effects
  assert list.all(transcript.effects, fn(effect) {
    case effect {
      transcript.Fetch(by: transcript.ModuleCache, ..) -> True
      _ -> False
    }
  })
}

fn fake(responses: List(List(BitArray)), requests) {
  let remaining = mutable_reference.new(responses)
  fn(request: request.Request(BitArray)) {
    mutable_reference.set(requests, [request, ..mutable_reference.get(requests)])
    let chunks = case mutable_reference.get(remaining) {
      [chunks, ..rest] -> {
        mutable_reference.set(remaining, rest)
        chunks
      }
      [] -> []
    }
    promise.resolve(Ok(response.Response(200, [], session.reader(chunks))))
  }
}

pub fn ollama_cloud_requests_go_to_ollama_test() {
  let requests = mutable_reference.new([])
  let responses = [
    agent.stream(Reply("", ["!int_add(1, 1)"])),
    agent.stream(Reply("Two", [])),
  ]
  let assert model.Provider(llm:, ..) =
    model.ollama_cloud("gpt-oss:120b", "key")
  let model = model.Provider(llm:, transport: fake(responses, requests))
  let config = session.Config(..config(agent.null(), ["add"]), model:)
  use transcript <- promise.map(session.run(config))
  let assert [run] = transcript.runs(transcript)
  assert transcript.Computed(v.Integer(2)) == run.outcome
  let assert [second, first] = mutable_reference.get(requests)
  assert "ollama.com" == first.host
  assert "/api/chat" == first.path
  assert Ok("Bearer key") == request.get_header(first, "authorization")
  let assert Ok(body) = bit_array.to_string(second.body)
  assert string.contains(body, "\"model\":\"gpt-oss:120b\"")
  assert "ollama/gpt-oss:120b" == model.describe(model)
}

pub fn mistral_requests_go_to_mistral_test() {
  let requests = mutable_reference.new([])
  let call =
    "data: {\"choices\":[{\"delta\":{\"content\":\"\",\"tool_calls\":[{\"id\":\"c1\",\"index\":0,\"function\":{\"name\":\"run\",\"arguments\":\"{\\\"code\\\":\\\"!int_add(2, 2)\\\"}\"}}]}}]}\n\ndata: [DONE]\n\n"
  let answer =
    "data: {\"choices\":[{\"delta\":{\"content\":\"Four\"}}]}\n\ndata: [DONE]\n\n"
  let responses = [[<<call:utf8>>], [<<answer:utf8>>]]
  let assert model.Provider(llm:, ..) =
    model.mistral("mistral-medium-latest", "key")
  let model = model.Provider(llm:, transport: fake(responses, requests))
  let config = session.Config(..config(agent.null(), ["add"]), model:)
  use transcript <- promise.map(session.run(config))
  let assert [run] = transcript.runs(transcript)
  assert transcript.Computed(v.Integer(4)) == run.outcome
  let assert [turn] = transcript.turns
  assert "Four" == transcript.reply(turn)
  let assert [_, first] = mutable_reference.get(requests)
  assert "api.mistral.ai" == first.host
  assert "/v1/chat/completions" == first.path
}

/// A provider that stops answering must not hold a run open.
pub fn a_stalled_provider_ends_the_session_test() {
  let stalled = fn(_) { promise.new(fn(_resolve) { Nil }) }
  let assert model.Provider(llm:, ..) =
    model.ollama_cloud("gpt-oss:120b", "key")
  let model = model.Provider(llm:, transport: model.with_timeout(stalled, 1))
  let config = session.Config(..config(agent.null(), ["add"]), model:)
  use transcript <- promise.map(session.run(config))
  let assert transcript.ModelFailed(reason) = transcript.stop
  assert string.contains(reason, "no answer within 1s")
  assert [] == transcript.runs(transcript)
}

/// A stream that stops mid answer has the same deadline as the request.
pub fn a_stalled_stream_ends_the_session_test() {
  let stalling = fn(_) {
    promise.resolve(
      Ok(response.Response(200, [], fn() { promise.new(fn(_resolve) { Nil }) })),
    )
  }
  let assert model.Provider(llm:, ..) =
    model.ollama_cloud("gpt-oss:120b", "key")
  let model = model.Provider(llm:, transport: model.with_timeout(stalling, 1))
  let config = session.Config(..config(agent.null(), ["add"]), model:)
  use transcript <- promise.map(session.run(config))
  let assert transcript.ModelFailed(reason) = transcript.stop
  assert string.contains(reason, "no answer within 1s")
}
