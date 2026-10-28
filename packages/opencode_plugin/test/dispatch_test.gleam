//// Consume the actual standalone dispatcher with the official AI SDK tool API.

import envoy
import gleam/dict
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/string
import javascript/mutable_reference as reference
import opencode_plugin/native as n
import opencode_plugin/sdk
import plinthx/javascript/foreign
import plinthx/javascript/module
import plinthx/node/fs
import simplifile

fn data(text) {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

fn invoke(function, arguments) {
  foreign.apply(function, gleam_array(arguments))
}

fn gleam_array(values) {
  array.from_list(values)
}

fn with_fixture(check) {
  let before = envoy.get("OPENCODE_EYG")
  let config = envoy.get("OPENCODE_EYG_CONFIG")
  envoy.set("OPENCODE_EYG", "only")
  envoy.unset("OPENCODE_EYG_CONFIG")
  let assert Ok(root) = fs.temporary_directory("eyg-roadmap-opencode-")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/.opencode")
  let assert Ok(_) =
    simplifile.write(
      root <> "/.opencode/eyg.eyg",
      "{policy: {shout: Pass, timing: (_) -> { Mock(Ok(\"mocked\")) }, task: Pass}}",
    )
  let assert Ok(cwd) = simplifile.current_directory()
  use loaded <- promise.await(module.load(cwd <> "/dist/dispatch.mjs"))
  let assert Ok(api) = loaded
  let checked = check(api, root) |> promise.map(Ok) |> promise.rescue(Error)
  use checked <- promise.map(checked)
  let assert Ok(_) = simplifile.delete(root)
  restore("OPENCODE_EYG", before)
  restore("OPENCODE_EYG_CONFIG", config)
  case checked {
    Ok(_) -> Nil
    Error(error) -> foreign.raise(error)
  }
}

fn restore(name, value) {
  case value {
    Ok(value) -> envoy.set(name, value)
    Error(_) -> envoy.unset(name)
  }
}

fn input(root, id, parent) {
  n.object([
    #(
      "session",
      n.object([
        #("id", n.data(id)),
        #("directory", n.data(root)),
        #("parentID", n.data(parent)),
      ]),
    ),
    #("agent", n.object([#("name", n.data("build"))])),
  ])
}

fn wrap(api, root, native, id, parent) {
  invoke(n.field(api, "wrap_tools"), [
    native,
    input(root, id, parent),
    n.data(fn(_) { promise.resolve(n.object([])) }),
  ])
  |> foreign.to_promise
}

fn native_tool(description, schema, execute) {
  sdk.tool(
    n.object([
      #("description", n.data(description)),
      #("inputSchema", sdk.json_schema(data(schema))),
      #("execute", n.data(execute)),
    ]),
  )
}

fn options() {
  n.object([
    #("toolCallId", n.data("outer")),
    #("abortSignal", n.object([#("marker", n.data("same signal"))])),
  ])
}

fn eyg(api, code) {
  n.call(n.field(api, "eyg"), "execute", [
    n.object([#("code", n.data(code))]),
    options(),
  ])
  |> foreign.to_promise
}

pub fn native_callbacks_keep_host_options_and_outer_program_metadata_test() {
  use api, root <- with_fixture()
  let executed = reference.new(0)
  let schema =
    "{\"type\":\"object\",\"properties\":{\"textValue\":{\"type\":\"string\"}},\"required\":[\"textValue\"]}"
  let shout =
    native_tool("Uppercase text", schema, fn(args, options) {
      let _ = reference.set(executed, reference.get(executed) + 1)
      assert n.string(args, "textValue") == "hello"
      assert n.string(options, "toolCallId") == "outer"
      assert n.string(n.field(options, "abortSignal"), "marker")
        == "same signal"
      let original = n.call(api, "outer_args", [options, args])
      assert n.string(original, "code")
        == "perform Shout({text_value: \"hello\"})"
      promise.resolve(
        n.object([#("title", n.data("native")), #("output", n.data("HELLO"))]),
      )
    })
  let native = n.object([#("shout", shout)])
  use wrapped <- promise.await(wrap(api, root, native, "top", ""))
  assert list.length(dict_keys(wrapped)) == 1
  use output <- promise.map(eyg(
    wrapped,
    "perform Shout({text_value: \"hello\"})",
  ))
  assert n.string(output, "output") == "Ok(\"HELLO\")"
  assert reference.get(executed) == 1
}

fn dict_keys(value) {
  n.fields(value) |> dict.keys
}

pub fn only_gate_and_off_use_the_same_native_dispatcher_test() {
  use api, root <- with_fixture()
  let executed = reference.new(0)
  let tool =
    native_tool("Clock", "{\"type\":\"object\"}", fn(_, _) {
      let _ = reference.set(executed, reference.get(executed) + 1)
      promise.resolve(n.object([#("output", n.data("performed"))]))
    })
  let native = n.object([#("timing", tool), #("secret", tool)])
  use wrapped <- promise.await(wrap(api, root, native, "top", ""))
  assert dict_keys(wrapped) == ["eyg"]
  use denied <- promise.await(eyg(wrapped, "perform Secret({})"))
  assert string.contains(
    n.string(denied, "output"),
    "not allowed by your policy",
  )
  envoy.set("OPENCODE_EYG", "gate")
  use wrapped <- promise.await(wrap(api, root, native, "top", ""))
  use mocked <- promise.await(
    n.call(n.field(wrapped, "timing"), "execute", [n.object([]), options()])
    |> foreign.to_promise,
  )
  assert n.string(mocked, "output") == "mocked"
  assert reference.get(executed) == 0
  envoy.set("OPENCODE_EYG", "off")
  use wrapped <- promise.await(wrap(api, root, native, "top", ""))
  use output <- promise.map(
    n.call(n.field(wrapped, "timing"), "execute", [n.object([]), options()])
    |> foreign.to_promise,
  )
  assert n.string(output, "output") == "performed"
  assert reference.get(executed) == 1
}

pub fn actual_task_metadata_stores_the_policy_before_reentrant_child_calls_test() {
  use api, root <- with_fixture()
  let child_text = reference.new("")
  let native = reference.new(n.object([]))
  let shout =
    native_tool("Shout", "{\"type\":\"object\"}", fn(_, _) {
      promise.resolve(n.object([#("output", n.data("leaked real call"))]))
    })
  let task =
    native_tool(
      "Task",
      "{\"type\":\"object\",\"properties\":{\"subagent_type\":{\"type\":\"string\"}}}",
      fn(args, options) {
        assert !foreign.has_own(args, "policy")
        let _ =
          n.call(api, "notify", [
            options,
            n.object([
              #("metadata", n.object([#("sessionId", n.data("child"))])),
            ]),
          ])
        use child <- promise.await(wrap(
          api,
          root,
          reference.get(native),
          "child",
          "top",
        ))
        use reply <- promise.map(eyg(child, "perform Shout({})"))
        let _ = reference.set(child_text, n.string(reply, "output"))
        n.object([#("output", n.data("child finished"))])
      },
    )
  let _ = reference.set(native, n.object([#("shout", shout), #("task", task)]))
  use wrapped <- promise.await(wrap(api, root, reference.get(native), "top", ""))
  use reply <- promise.await(eyg(
    wrapped,
    "perform Task({subagent_type: \"reader\", policy: {shout: (_) -> { Mock(Ok(\"child mock\")) }}})",
  ))
  assert n.string(reply, "output") == "Ok(\"child finished\")"
  assert reference.get(child_text) == "Ok(\"child mock\")"
  use child <- promise.await(wrap(
    api,
    root,
    reference.get(native),
    "child",
    "top",
  ))
  use denied <- promise.map(eyg(
    child,
    "perform Task({subagent_type: \"reader\"})",
  ))
  assert string.contains(
    n.string(denied, "output"),
    "not allowed by your policy",
  )
}
