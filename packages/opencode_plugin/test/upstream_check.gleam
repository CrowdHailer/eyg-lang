//// Fetch the pinned upstream dispatcher, patch it and execute its real resolve
//// function with deterministic services and the actual AI SDK/Effect libraries.

import effect_library
import envoy
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/http/request
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/string
import javascript/mutable_reference as reference
import loam/system
import opencode_plugin/integration
import opencode_plugin/native as n
import opencode_plugin/sdk
import plinthx/bun/bundle
import plinthx/bun/runtime
import plinthx/javascript/foreign
import plinthx/javascript/module
import simplifile

const source =
  "https://raw.githubusercontent.com/anomalyco/opencode/v1.19.0/packages/opencode/src/session/tools.ts"

pub fn main() {
  let assert Ok(cwd) = simplifile.current_directory()
  let directory = cwd <> "/build/upstream-dispatch"
  let assert Ok(_) = simplifile.create_directory_all(directory)
  use response <- promise.await(fetch_source(directory))
  let assert Ok(code) = response
  let assert Ok(patched) = integration.patch(code)
  assert integration.patch(patched) == Ok(patched)
  let assert Ok(_) = simplifile.write(directory <> "/tools.ts", patched)
  let compiled_host =
    cwd <> "/build/dev/javascript/opencode_plugin/upstream_host.mjs"
  let exports =
    "Plugin, Permission, ToolRegistry, MCP, Truncate, RuntimeFlags, Session, EffectBridge, ProviderTransform, ToolJsonSchema, McpCatalog, ModelV2, ProviderV2, PartID, isRecord, Agent, SessionV1, Provider, Tool, MessageV2, SessionProcessor"
  let assert Ok(_) =
    simplifile.write(
      directory <> "/host.mjs",
      "import { create } from "
        <> json.to_string(json.string(compiled_host))
        <> ";\nexport const host = create();\nexport const { "
        <> exports
        <> " } = host;\n",
    )
  let assert Ok(_) =
    simplifile.write(
      directory <> "/entry.mjs",
      "export { resolve } from './tools.ts';\nexport { host } from './host.mjs';\n",
    )
  let aliases =
    [
      "@/provider/transform", "@/mcp", "@/mcp/catalog", "@/permission",
      "@/tool/json-schema", "@/tool/registry", "@/tool/truncate", "@/plugin",
      "@/effect/bridge", "@opencode-ai/core/provider", "@opencode-ai/core/model",
      "@/util/record", "@/effect/runtime-flags", "./session", "./schema",
      "@/agent/agent", "@opencode-ai/core/v1/session", "@/provider/provider",
      "@/tool/tool",
    ]
    |> list.filter(fn(name) { !string.starts_with(name, "./") })
    |> list.map(fn(name) {
      #(name, json.array([directory <> "/host.mjs"], json.string))
    })
  let assert Ok(_) =
    simplifile.write(
      directory <> "/tsconfig.json",
      json.to_string(
        json.object([
          #(
            "compilerOptions",
            json.object([
              #("baseUrl", json.string(".")),
              #(
                "paths",
                json.object([
                  #(
                    "@/tool/eyg/dispatch.mjs",
                    json.array([cwd <> "/dist/dispatch.mjs"], json.string),
                  ),
                  ..aliases
                ]),
              ),
            ]),
          ),
        ]),
      ),
    )
  let assert Ok(_) =
    simplifile.write(
      directory <> "/session.ts",
      "export { Session } from './host.mjs';\n",
    )
  let assert Ok(_) =
    simplifile.write(
      directory <> "/schema.ts",
      "export { PartID } from './host.mjs';\n",
    )
  let assert Ok(_) =
    simplifile.write(
      directory <> "/message-v2.ts",
      "export { MessageV2 } from './host.mjs';\n",
    )
  let assert Ok(_) =
    simplifile.write(
      directory <> "/processor.ts",
      "export { SessionProcessor } from './host.mjs';\n",
    )
  let options =
    json.object([
      #("entrypoints", json.array([directory <> "/entry.mjs"], json.string)),
      #("outdir", json.string(directory <> "/built")),
      #("naming", json.object([#("entry", json.string("[name].mjs"))])),
      #("format", json.string("esm")),
      #("target", json.string("node")),
      #("throw", json.bool(False)),
      #(
        "external",
        json.array(["ai", "effect", "@opencode-ai/plugin"], json.string),
      ),
    ])
    |> json.to_string
  let assert Ok(bun) = runtime.get()
  use built <- promise.await(bundle.build(bun, options))
  let assert Ok(built) = built
  assert bundle.success(built) as string.join(bundle.logs(built), "\n")
  use loaded <- promise.await(module.load(directory <> "/built/entry.mjs"))
  let assert Ok(loaded) = loaded
  check(loaded, directory)
}

fn fetch_source(directory) {
  let cached = directory <> "/original-tools.ts"
  case simplifile.read(cached) {
    Ok(code) -> {
      assert integration.digest(code) == integration.source_sha256
      promise.resolve(Ok(code))
    }
    Error(_) -> {
      let assert Ok(request) = request.to(source)
      use response <- promise.map(
        system.run(system.fetch(request.set_body(request, <<>>))),
      )
      let assert Ok(response) = response
      assert response.status == 200
      let assert Ok(code) = bit_array.to_string(response.body)
      assert integration.digest(code) == integration.source_sha256
      let assert Ok(_) = simplifile.write(cached, code)
      Ok(code)
    }
  }
}

fn data(text) {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

fn input(root, id, parent, metadata, completed) {
  n.object([
    #(
      "agent",
      n.object([#("name", n.data("build")), #("permission", n.array([]))]),
    ),
    #(
      "model",
      n.object([
        #("providerID", n.data("fixture")),
        #("api", n.object([#("id", n.data("fixture"))])),
      ]),
    ),
    #(
      "session",
      n.object([
        #("id", n.data(id)),
        #("parentID", n.data(parent)),
        #("directory", n.data(root)),
        #("permission", n.array([])),
      ]),
    ),
    #(
      "processor",
      n.object([
        #("message", n.object([#("id", n.data("message"))])),
        #(
          "updateToolCall",
          n.data(fn(_id, update) {
            let part =
              n.object([
                #(
                  "state",
                  n.object([
                    #("status", n.data("running")),
                    #("time", n.object([#("start", n.data(0))])),
                  ]),
                ),
              ])
            let changed = foreign.apply(update, array.from_list([part]))
            let _ =
              reference.set(
                metadata,
                n.field(n.field(changed, "state"), "input"),
              )
            n.call(effect_library.effect(), "succeed", [changed])
          }),
        ),
        #(
          "completeToolCall",
          n.data(fn(_id, _output) {
            let _ = reference.set(completed, reference.get(completed) + 1)
            n.call(effect_library.effect(), "succeed", [n.data(Nil)])
          }),
        ),
      ]),
    ),
    #("bypassAgentCheck", n.data(False)),
    #("messages", n.array([])),
    #("promptOps", n.object([])),
  ])
}

fn resolve(loaded, input) {
  let source = n.call(loaded, "resolve", [input])
  n.call(n.field(loaded, "host"), "run", [source]) |> foreign.to_promise
}

fn eyg(tools, code, aborted) {
  n.call(n.field(tools, "eyg"), "execute", [
    n.object([#("code", n.data(code))]),
    n.object([
      #("toolCallId", n.data("outer")),
      #("abortSignal", n.object([#("aborted", n.data(aborted))])),
    ]),
  ])
  |> foreign.to_promise
}

fn check(loaded, directory) {
  let root = directory <> "/project"
  let assert Ok(_) = simplifile.create_directory_all(root <> "/.opencode")
  let assert Ok(_) =
    simplifile.write(
      root <> "/.opencode/eyg.eyg",
      "{policy: {shout: Pass, timing: (_) -> { Mock(Ok(\"mocked\")) }, task: Pass, mcp_fixture_echo: Pass}}",
    )
  let old_mode = envoy.get("OPENCODE_EYG")
  let old_config = envoy.get("OPENCODE_EYG_CONFIG")
  envoy.set("OPENCODE_EYG", "only")
  envoy.unset("OPENCODE_EYG_CONFIG")
  let checked =
    run_checks(loaded, root) |> promise.map(Ok) |> promise.rescue(Error)
  use checked <- promise.map(checked)
  let assert Ok(_) = simplifile.delete(root)
  restore("OPENCODE_EYG", old_mode)
  restore("OPENCODE_EYG_CONFIG", old_config)
  case checked {
    Ok(_) -> io.println("PASS actual OpenCode v1.19.0 dispatcher")
    Error(error) -> foreign.raise(error)
  }
}

fn restore(name, value) {
  case value {
    Ok(value) -> envoy.set(name, value)
    Error(_) -> envoy.unset(name)
  }
}

fn run_checks(loaded, root) {
  let host = n.field(loaded, "host")
  let effect = n.field(host, "effect")
  let metadata = reference.new(n.object([]))
  let completed = reference.new(0)
  let called = reference.new([])
  let child_tools = reference.new(n.object([]))
  let child_text = reference.new("")
  let schema =
    data(
      "{\"type\":\"object\",\"properties\":{\"textValue\":{\"type\":\"string\"}}}",
    )
  let native = fn(name) {
    n.object([
      #("id", n.data(name)),
      #("description", n.data(name)),
      #("jsonSchema", schema),
      #(
        "execute",
        n.data(fn(args, ctx) {
          let _ = reference.set(called, [name, ..reference.get(called)])
          let request =
            n.object([
              #("permission", n.data(name)),
              #("patterns", n.array([n.data("*")])),
              #("metadata", n.object([])),
            ])
          n.call(effect, "flatMap", [
            n.call(ctx, "ask", [request]),
            n.data(fn(_) {
              n.call(effect, "map", [
                n.call(ctx, "metadata", [
                  n.object([
                    #("title", n.data(name)),
                    #("metadata", n.object([])),
                  ]),
                ]),
                n.data(fn(_) {
                  n.object([
                    #("title", n.data(name)),
                    #("metadata", n.object([])),
                    #(
                      "output",
                      n.data(case name {
                        "shout" -> string.uppercase(n.string(args, "textValue"))
                        _ -> "native " <> name
                      }),
                    ),
                  ])
                }),
              ])
            }),
          ])
        }),
      ),
    ])
  }
  let task =
    n.object([
      #("id", n.data("task")),
      #("description", n.data("task")),
      #(
        "jsonSchema",
        data(
          "{\"type\":\"object\",\"properties\":{\"subagent_type\":{\"type\":\"string\"}}}",
        ),
      ),
      #(
        "execute",
        n.data(fn(args, ctx) {
          assert !foreign.has_own(args, "policy")
          n.call(effect, "flatMap", [
            n.call(ctx, "metadata", [
              n.object([
                #("title", n.data("child")),
                #("metadata", n.object([#("sessionId", n.data("child"))])),
              ]),
            ]),
            n.data(fn(_) {
              n.call(effect, "promise", [
                n.data(fn(_signal) {
                  use child <- promise.await(resolve(
                    loaded,
                    input(root, "child", "top", metadata, completed),
                  ))
                  let _ = reference.set(child_tools, child)
                  use reply <- promise.map(eyg(
                    child,
                    "perform Shout({text_value: \"untrusted child\"})",
                    False,
                  ))
                  let _ = reference.set(child_text, n.string(reply, "output"))
                  n.object([
                    #("title", n.data("task")),
                    #("metadata", n.object([])),
                    #("output", n.data("child finished")),
                  ])
                }),
              ])
            }),
          ])
        }),
      ),
    ])
  let registry =
    n.array([native("shout"), native("timing"), native("secret"), task])
  let mcp_echo =
    sdk.tool(
      n.object([
        #("description", n.data("MCP echo")),
        #("inputSchema", sdk.json_schema(schema)),
        #(
          "execute",
          n.data(fn(args, _options) {
            promise.resolve(
              n.object([
                #(
                  "content",
                  n.array([
                    n.object([
                      #("type", n.data("text")),
                      #("text", n.data("MCP:" <> n.string(args, "textValue"))),
                    ]),
                  ]),
                ),
              ]),
            )
          }),
        ),
      ]),
    )
  let mcp = n.object([#("mcp__fixture__echo", n.object([#("def", mcp_echo)]))])
  let _ = n.call(host, "configure", [registry, mcp, n.data(False)])
  let top = input(root, "top", "", metadata, completed)
  use tools <- promise.await(resolve(loaded, top))
  assert dict.keys(n.fields(tools)) == ["eyg"]
  let code = "perform Shout({text_value: \"hello\"})"
  use reply <- promise.await(eyg(tools, code, False))
  assert n.string(reply, "output") == "Ok(\"HELLO\")"
    as n.string(reply, "output")
  assert n.string(reference.get(metadata), "code") == code
  let events = n.list(n.call(host, "events", [])) |> list.map(n.text)
  assert events
    == [
      "tool.execute.before:shout",
      "permission:shout",
      "tool.execute.after:shout",
    ]
    as string.inspect(events)
  use reply <- promise.await(eyg(tools, "perform Timing({})", False))
  assert n.string(reply, "output") == "Ok(\"mocked\")"
  use reply <- promise.await(eyg(tools, "perform Secret({})", False))
  assert string.contains(
    n.string(reply, "output"),
    "not allowed by your policy",
  )
  assert reference.get(called) == ["shout"]
  io.println(
    "PASS native tools: Shout -> HELLO; Timing mocked; Secret unavailable; original input, hooks and permissions retained",
  )
  use reply <- promise.await(eyg(
    tools,
    "perform McpFixtureEcho({text_value: \"hello\"})",
    False,
  ))
  assert n.string(reply, "output") == "Ok(\"MCP:hello\")"
    as n.string(reply, "output")
  assert list.contains(
    n.list(n.call(host, "events", [])) |> list.map(n.text),
    "permission:mcp__fixture__echo",
  )
  io.println("PASS MCP tools use their normal permission and event pipeline")
  use reply <- promise.await(eyg(
    tools,
    "perform Task({subagent_type: \"reader\", policy: {shout: (_) -> { Mock(Ok(\"child mock\")) }}})",
    False,
  ))
  assert n.string(reply, "output") == "Ok(\"child finished\")"
  assert reference.get(child_text) == "Ok(\"child mock\")"
  use reply <- promise.await(eyg(
    reference.get(child_tools),
    "perform Task({subagent_type: \"reader\"})",
    False,
  ))
  assert string.contains(
    n.string(reply, "output"),
    "not allowed by your policy",
  )
  io.println(
    "PASS Task metadata sets child policy before its first call and later calls retain it",
  )
  envoy.set("OPENCODE_EYG", "gate")
  use gated <- promise.await(resolve(loaded, top))
  use reply <- promise.await(
    n.call(n.field(gated, "shout"), "execute", [
      n.object([#("textValue", n.data("gate"))]),
      n.object([
        #("toolCallId", n.data("direct")),
        #("abortSignal", n.object([#("aborted", n.data(False))])),
      ]),
    ])
    |> foreign.to_promise,
  )
  assert n.string(reply, "output") == "GATE"
  use reply <- promise.await(
    n.call(n.field(gated, "timing"), "execute", [n.object([]), n.object([])])
    |> foreign.to_promise,
  )
  assert n.string(reply, "output") == "mocked"
  envoy.set("OPENCODE_EYG", "only")
  let _ = n.call(host, "configure", [registry, mcp, n.data(True)])
  use early <- promise.await(resolve(loaded, top))
  assert dict.keys(n.fields(early)) == ["eyg"]
  use _ <- promise.await(eyg(
    early,
    "perform Shout({text_value: \"abort\"})",
    True,
  ))
  assert reference.get(completed) == 1
  envoy.set("OPENCODE_EYG", "off")
  use original <- promise.map(resolve(loaded, top))
  assert !foreign.has_own(original, "eyg")
  assert foreign.has_own(original, "secret")
  io.println(
    "PASS gate/off modes, early dispatcher return and cancellation completion hook",
  )
}
