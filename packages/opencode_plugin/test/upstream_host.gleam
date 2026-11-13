//// Deterministic services around the actual upstream SessionTools.resolve.
//// All fixture behavior is Gleam; the unmodified host dispatch stays upstream.

import effect_library
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/array
import gleam/list
import javascript/mutable_reference as reference
import opencode_plugin/native as n
import plinthx/javascript/foreign

pub fn create() {
  let effect = effect_library.effect()
  let context = effect_library.context()
  let names = [
    "Plugin",
    "Permission",
    "ToolRegistry",
    "MCP",
    "Truncate",
    "RuntimeFlags",
    "Session",
  ]
  let tags =
    names
    |> list.map(fn(name) {
      #(name, n.call(context, "Service", [n.data("EYG fixture " <> name)]))
    })
    |> dict.from_list
  let provided = reference.new(n.call(context, "empty", []))
  let events = reference.new([])
  let next_part = reference.new(0)
  let success = fn(value) { n.call(effect, "succeed", [value]) }
  let run = fn(value) {
    foreign.apply(
      n.call(effect, "runPromiseWith", [reference.get(provided)]),
      array.from_list([value]),
    )
  }
  let record = fn(kind) {
    let _ = reference.set(events, [kind, ..reference.get(events)])
    Nil
  }
  let configure = fn(registry, mcp_tools, code_mode) {
    let services = [
      #(
        "Plugin",
        n.object([
          #(
            "trigger",
            n.data(fn(name, input, output) {
              record(n.text(name) <> ":" <> n.string(input, "tool"))
              success(output)
            }),
          ),
        ]),
      ),
      #(
        "Permission",
        n.object([
          #(
            "ask",
            n.data(fn(input) {
              record("permission:" <> n.string(input, "permission"))
              success(n.data(Nil))
            }),
          ),
        ]),
      ),
      #(
        "ToolRegistry",
        n.object([#("tools", n.data(fn(_) { success(registry) }))]),
      ),
      #(
        "MCP",
        n.object([
          #("clients", n.data(fn() { success(n.object([])) })),
          #("tools", n.data(fn() { success(mcp_tools) })),
        ]),
      ),
      #(
        "Truncate",
        n.object([
          #(
            "output",
            n.data(fn(text, _options, _agent) {
              success(
                n.object([#("content", text), #("truncated", n.data(False))]),
              )
            }),
          ),
        ]),
      ),
      #("RuntimeFlags", n.object([#("experimentalCodeMode", code_mode)])),
      #(
        "Session",
        n.object([#("get", n.data(fn(id) { success(n.object([#("id", id)])) }))]),
      ),
    ]
    let provided_context =
      list.fold(services, n.call(context, "empty", []), fn(provided, service) {
        let assert Ok(tag) = dict.get(tags, service.0)
        n.call(context, "add", [provided, tag, service.1])
      })
    let _ = reference.set(provided, provided_context)
    let _ = reference.set(events, [])
    Nil
  }
  let modules =
    names
    |> list.map(fn(name) {
      let assert Ok(tag) = dict.get(tags, name)
      let fields = [#("Service", tag)]
      let fields = case name {
        "Permission" -> [
          #(
            "merge",
            n.data(fn(a, b) { n.array(list.append(n.list(a), n.list(b))) }),
          ),
          ..fields
        ]
        _ -> fields
      }
      #(name, n.object(fields))
    })
  let identity =
    n.object([#("ID", n.object([#("make", n.data(fn(value) { value }))]))])
  n.object([
    #("configure", n.data(configure)),
    #("run", n.data(run)),
    #(
      "events",
      n.data(fn() {
        n.array(list.reverse(reference.get(events)) |> list.map(n.data))
      }),
    ),
    #("effect", effect),
    #(
      "EffectBridge",
      n.object([
        #(
          "make",
          n.data(fn() { success(n.object([#("promise", n.data(run))])) }),
        ),
      ]),
    ),
    #(
      "ProviderTransform",
      n.object([#("schema", n.data(fn(_, schema) { schema }))]),
    ),
    #(
      "ToolJsonSchema",
      n.object([#("fromTool", n.data(fn(tool) { n.field(tool, "jsonSchema") }))]),
    ),
    #(
      "McpCatalog",
      n.object([
        #(
          "convertTool",
          n.data(fn(definition, _client, _timeout) { definition }),
        ),
      ]),
    ),
    #("ModelV2", identity),
    #("ProviderV2", identity),
    #(
      "PartID",
      n.object([
        #(
          "ascending",
          n.data(fn() {
            let value = reference.get(next_part) + 1
            let _ = reference.set(next_part, value)
            "fixture-part-" <> int.to_string(value)
          }),
        ),
      ]),
    ),
    #(
      "isRecord",
      n.data(fn(value) {
        case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
          Ok(_) -> True
          Error(_) -> False
        }
      }),
    ),
    ..modules
  ])
}
