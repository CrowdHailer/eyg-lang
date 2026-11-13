import eyg/hub/cache
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict
import gleam/dynamic
import gleam/json
import gleam/list
import gleam/option.{None}
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool
import overlay/web/artifact
import overlay/web/context
import overlay/web/puppet
import overlay/web/tools
import overlay/web/trace
import pal/system

fn run(ctx, code) {
  tools.execute_all(ctx, [
    tool.Call(
      "call",
      tool.FunctionCall("run", dict.from_list([#("code", utils.String(code))])),
    ),
  ])
}

fn shown() {
  let ctx =
    tools.Context(
      trace: trace.new_session(0),
      cache: cache.ready(),
      counter: 0,
      effects: [],
      context: context.default(),
      artifacts: artifact.new(),
      policy: None,
      workspace: None,
    )
  let #(ctx, _) =
    run(
      ctx,
      "let _ = perform Artifact({name: \"map\", bundle: [{path: \"index.html\", media_type: \"text/html\", content: !string_to_binary(\"<h1>Map</h1>\")}]})
perform Show({item: Artifact(\"map\"), origin: {x: 0, y: 0}, size: {x: 1000, y: 1000}})",
    )
  tools.Context(..ctx, effects: [])
}

fn reply(fields: List(#(String, dynamic.Dynamic))) {
  dynamic.properties(
    list.map(fields, fn(field) {
      let #(key, value) = field
      #(dynamic.string(key), value)
    }),
  )
}

pub fn artifact_must_be_shown_test() {
  let ctx = tools.Context(..shown(), artifacts: artifact.new())
  let #(_, calls) =
    run(
      ctx,
      "perform Puppet({page: Artifact(\"map\"), locator: [], action: Count({}), timeout: 100})",
    )
  let assert [tools.Progress(call: tools.Successful(value), ..)] = calls
  assert v.error(v.String("map is not shown, use Show before Puppet")) == value
}

pub fn request_is_sent_to_the_preview_frame_test() {
  let #(ctx, calls) =
    run(
      shown(),
      "perform Puppet({page: Artifact(\"map\"), locator: [Role({role: \"heading\", name: \"Map\"}), Nth(0)], action: Expect(ToHaveText(\"Map\")), timeout: 2000})",
    )
  let assert [
    tools.Progress(call: tools.Handling(id, screenshot: False, ..), ..),
  ] = calls
  let assert [system.RequestFrame(selector:, message:, timeout: 7000, resume:)] =
    ctx.effects
  assert "iframe.artifact-preview[data-artifact=\"map\"][data-version=\"latest\"]"
    == selector
  assert "{\"locator\":[{\"type\":\"role\",\"role\":\"heading\",\"name\":\"Map\"},{\"type\":\"nth\",\"value\":0}],\"action\":{\"type\":\"expect\",\"condition\":{\"type\":\"to_have_text\",\"value\":\"Map\"}},\"timeout\":2000}"
    == json.to_string(message)

  let assert system.Done(#(done_id, value)) =
    resume(Ok(reply([#("type", dynamic.string("done"))])))
  assert id == done_id
  let #(_, calls) = tools.effect_handled(ctx, calls, id, value)
  let assert [tools.Progress(call: tools.Successful(value), ..)] = calls
  assert v.ok(v.Tagged("Done", v.unit())) == value
}

pub fn failures_and_replies_resume_the_program_test() {
  let #(ctx, _) =
    run(
      shown(),
      "perform Puppet({page: Artifact(\"map\"), locator: [Css(\"li\")], action: AllTextContents({}), timeout: 100})",
    )
  let assert [system.RequestFrame(resume:, ..)] = ctx.effects
  let assert system.Done(#(_, value)) = resume(Error("No reply from frame"))
  assert v.error(v.String("No reply from frame")) == value
  let assert system.Done(#(_, value)) =
    resume(
      Ok(
        reply([
          #("type", dynamic.string("error")),
          #("value", dynamic.string("css=\"li\" matched no elements")),
        ]),
      ),
    )
  assert v.error(v.String("css=\"li\" matched no elements")) == value
  let assert system.Done(#(_, value)) =
    resume(
      Ok(
        reply([
          #("type", dynamic.string("texts")),
          #("value", dynamic.list([dynamic.string("a"), dynamic.string("b")])),
        ]),
      ),
    )
  assert v.ok(v.Tagged("Texts", v.LinkedList([v.String("a"), v.String("b")])))
    == value
  let assert system.Done(#(_, value)) =
    resume(Ok(reply([#("type", dynamic.string("unknown"))])))
  assert v.error(v.String("Unexpected reply from artifact")) == value
}

pub fn screenshots_are_shown_to_the_agent_test() {
  let #(ctx, calls) =
    run(
      shown(),
      "let _ = perform Puppet({page: Artifact(\"map\"), locator: [], action: Screenshot({}), timeout: 100})
5",
    )
  let assert [
    tools.Progress(call: tools.Handling(id, screenshot: True, ..), ..),
  ] = calls
  let assert [system.RequestFrame(resume:, ..)] = ctx.effects
  let png = <<137, 80, 78, 71>>
  let url = "data:image/png;base64," <> bit_array.base64_encode(png, True)
  let assert system.Done(#(_, value)) =
    resume(
      Ok(
        reply([
          #("type", dynamic.string("image")),
          #("value", dynamic.string(url)),
        ]),
      ),
    )
  assert v.ok(v.Tagged("Image", v.Binary(png))) == value
  let #(_, calls) = tools.effect_handled(ctx, calls, id, value)
  let assert Ok([chat.ToolResultMessage(text: "5", images:, ..)]) =
    tools.all_returns(calls)
  assert [bit_array.base64_encode(png, True)] == images
}

pub fn revisions_have_their_own_frame_test() {
  let store = shown().artifacts
  let assert Ok(store) =
    artifact.show(
      store,
      artifact.Placement(
        artifact.Revision("map", 1),
        artifact.Point(0, 0),
        artifact.Point(10, 10),
      ),
    )
  assert Ok(
      "iframe.artifact-preview[data-artifact=\"map\"][data-version=\"1\"]",
    )
    == puppet.frame_selector(store, artifact.Revision("map", 1))
  assert Error("map · history is not shown, use Show before Puppet")
    == puppet.frame_selector(store, artifact.History("map"))
  let assert Ok(#(store, _)) =
    artifact.save(store, "say \"hi\"", [
      artifact.File("index.html", "text/html", <<>>),
    ])
  let assert Ok(store) =
    artifact.show(
      store,
      artifact.Placement(
        artifact.Artifact("say \"hi\""),
        artifact.Point(0, 0),
        artifact.Point(10, 10),
      ),
    )
  assert Ok(
      "iframe.artifact-preview[data-artifact=\"say \\\"hi\\\"\"][data-version=\"latest\"]",
    )
    == puppet.frame_selector(store, artifact.Artifact("say \"hi\""))
}
