import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import javascript/mutable_reference as reference
import opencode_plugin as core
import opencode_plugin/router.{type Tool, Session, Tool}
import plinthx/javascript/foreign

fn data(text) {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

fn object(fields) {
  foreign.object(array.from_list(fields))
}

fn configured() {
  use config <- promise.map(core.load_source(
    "{policy: {shout: Pass, timing: (_) -> { Mock(Ok(\"mocked\")) }, task: Pass}}",
    "/tmp/eyg-router-config.eyg",
  ))
  let assert Ok(config) = config
  router.new(config)
}

fn session(id, parent) {
  Session(id, parent, "/tmp", "build")
}

fn parent(_) {
  promise.resolve(None)
}

fn shout() {
  Tool(
    "shout",
    "Uppercase text",
    data(
      "{\"type\":\"object\",\"properties\":{\"textValue\":{\"type\":\"string\"}},\"required\":[\"textValue\"]}",
    ),
    fn(input, _) {
      let assert Ok(text) =
        decode.run(
          input,
          decode.field("textValue", decode.string, decode.success),
        )
      promise.resolve(string.uppercase(text))
    },
  )
}

fn run_tool(tool: Tool, input) {
  tool.execute(input, fn(_) { Nil })
}

pub fn only_mode_exposes_eyg_and_maps_native_schema_fields_test() {
  use router <- promise.await(configured())
  use wrapped <- promise.await(router.wrap(
    router,
    session("top", None),
    [shout()],
    parent,
    router.Only,
  ))
  let assert [tool] = wrapped
  assert tool.id == "eyg"
  assert string.contains(tool.description, "text_value: String")
  use output <- promise.map(run_tool(
    tool,
    object([
      #("code", foreign.to_dynamic("perform Shout({text_value: \"hello\"})")),
    ]),
  ))
  assert output == "Ok(\"HELLO\")"
}

pub fn direct_calls_share_mock_and_unavailable_effect_decisions_test() {
  use router <- promise.await(configured())
  let called = reference.new(0)
  let native = fn(name) {
    Tool(name, name, data("{\"type\":\"object\"}"), fn(_, _) {
      let _ = reference.set(called, reference.get(called) + 1)
      promise.resolve("performed")
    })
  }
  let available = [native("timing"), native("secret")]
  use wrapped <- promise.await(router.wrap(
    router,
    session("top", None),
    available,
    parent,
    router.Gate,
  ))
  let assert [_, timing, secret] = wrapped
  use mocked <- promise.await(run_tool(timing, object([])))
  assert mocked == "mocked"
  use denied <- promise.await(run_tool(secret, object([])))
  assert string.contains(denied, "not allowed by your policy")
  assert reference.get(called) == 0
  use unwrapped <- promise.await(router.wrap(
    router,
    session("off", None),
    available,
    parent,
    router.Off,
  ))
  let assert [timing, _] = unwrapped
  use result <- promise.map(run_tool(timing, object([])))
  assert result == "performed"
  assert reference.get(called) == 1
}

pub fn task_started_callback_preserves_the_child_policy_on_later_calls_test() {
  use router <- promise.await(configured())
  let available = [
    shout(),
    Tool(
      "task",
      "Start a child",
      data(
        "{\"type\":\"object\",\"properties\":{\"subagent_type\":{\"type\":\"string\"},\"prompt\":{\"type\":\"string\"}}}",
      ),
      fn(input, started) {
        assert !foreign.has_own(input, "policy")
        started("child")
        promise.resolve("started")
      },
    ),
  ]
  let top = session("top", None)
  let parent = fn(_) { promise.resolve(Some(top)) }
  use report <- promise.await(router.run(
    router,
    top,
    available,
    parent,
    "perform Task({subagent_type: \"reader\", prompt: \"go\", policy: {shout: (_) -> { Mock(Ok(\"child mock\")) }}})",
  ))
  assert report.ok
  use child <- promise.await(router.wrap(
    router,
    session("child", Some("top")),
    available,
    parent,
    router.Only,
  ))
  let assert [child] = child
  use output <- promise.await(run_tool(
    child,
    object([
      #("code", foreign.to_dynamic("perform Shout({text_value: \"real\"})")),
    ]),
  ))
  assert output == "Ok(\"child mock\")"
  use output <- promise.map(run_tool(
    child,
    object([
      #(
        "code",
        foreign.to_dynamic(
          "perform Task({subagent_type: \"reader\", prompt: \"denied\"})",
        ),
      ),
    ]),
  ))
  assert string.contains(output, "not allowed by your policy")
}
