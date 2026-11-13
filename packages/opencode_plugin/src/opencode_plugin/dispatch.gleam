//// Wrap OpenCode's existing AI SDK tool dispatcher. Host functions retain their
//// normal permission, validation, hook and cancellation path.

import envoy
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import opencode_plugin as core
import opencode_plugin/configuration
import opencode_plugin/native as n
import opencode_plugin/router
import opencode_plugin/sdk
import plinthx/javascript/foreign
import simplifile

fn mode() {
  case envoy.get("OPENCODE_EYG") {
    Ok("off") -> router.Off
    Ok("gate") -> router.Gate
    Ok("only") | Error(_) -> router.Only
    Ok(_) -> n.fail("OPENCODE_EYG must be only, gate or off")
  }
}

fn as_session(info, agent, directory) {
  let id = n.string(info, "id")
  let parent = case n.string(info, "parentID") {
    "" -> None
    id -> Some(id)
  }
  let directory = case n.string(info, "directory") {
    "" -> directory
    directory -> directory
  }
  router.Session(id:, parent:, directory:, agent:)
}

fn schemas(available) -> Promise(List(#(String, Dynamic, Dynamic))) {
  case available {
    [] -> promise.resolve([])
    [#(id, native), ..rest] -> {
      use schema <- promise.await(sdk.schema(n.field(native, "inputSchema")))
      use rest <- promise.map(schemas(rest))
      [#(id, native, schema), ..rest]
    }
  }
}

fn tools(available, options, outer) {
  list.map(available, fn(entry) {
    let #(id, native, schema) = entry
    router.Tool(
      id:,
      description: n.string(native, "description"),
      schema:,
      execute: fn(input, started) {
        let options =
          n.with_fields(options, [
            #("eygStarted", n.data(started)),
            #("eygArguments", outer),
          ])
        use output <- promise.map(
          n.call(native, "execute", [input, options]) |> foreign.to_promise,
        )
        case decode.run(output, decode.string) {
          Ok(text) -> text
          Error(_) -> n.string(output, "output")
        }
      },
    )
  })
}

fn response(report: core.Report) {
  let effects = list.unique(report.effects)
  let title = case effects {
    [] -> "pure"
    _ -> string.join(effects, ", ")
  }
  let output = case report.ok {
    True -> core.report_text(report)
    False -> "Error\n" <> core.report_text(report)
  }
  n.object([
    #("title", n.data(title)),
    #("output", n.data(output)),
    #(
      "metadata",
      n.object([
        #("ok", n.data(report.ok)),
        #("effects", n.data(array.from_list(effects))),
      ]),
    ),
  ])
}

/// Keep this function's returned closure for the process lifetime. Config changes
/// replace only that directory's router; child session policies survive later calls.
pub fn create(resources: Dynamic) {
  let default = n.string(resources, "dispatcher")
  let syntax = n.string(resources, "syntax")
  let builtins = n.string(resources, "builtins")
  let load = configuration.loader(default)
  fn(native: Dynamic, input: Dynamic, parent_callback: Dynamic) {
    case mode() {
      router.Off -> promise.resolve(native)
      mode -> {
        let info = n.field(input, "session")
        let assert Ok(cwd) = simplifile.current_directory()
        let directory = case n.string(info, "directory") {
          "" -> cwd
          directory -> directory
        }
        let session =
          as_session(info, n.string(n.field(input, "agent"), "name"), directory)
        let parent = fn(id) {
          use info <- promise.map(
            foreign.apply(parent_callback, array.from_list([n.data(id)]))
            |> foreign.to_promise,
          )
          case n.string(info, "id") {
            "" -> None
            _ -> Some(as_session(info, "", directory))
          }
        }
        let natives = n.fields(native) |> dict.to_list
        case dict.has_key(n.fields(native), "eyg") {
          True ->
            n.fail(
              "Remove the EYG plugin when using the native dispatcher integration",
            )
          False -> Nil
        }
        use available <- promise.await(schemas(natives))
        use loaded <- promise.await(load(directory))
        use description <- promise.map(router.describe(
          loaded.router,
          session,
          tools(available, n.object([]), n.object([])),
          parent,
        ))
        let run = fn(code, options, arguments) {
          use loaded <- promise.await(load(directory))
          router.run(
            loaded.router,
            session,
            tools(available, options, arguments),
            parent,
            code,
          )
          |> promise.map(response)
        }
        let assert Ok(code_schema) =
          json.parse(
            "{\"type\":\"object\",\"properties\":{\"code\":{\"type\":\"string\",\"description\":\"EYG source code\"}},\"required\":[\"code\"]}",
            decode.dynamic,
          )
        let eyg =
          sdk.tool(
            n.object([
              #(
                "description",
                n.data(description <> "\n\n" <> syntax <> "\n\n" <> builtins),
              ),
              #("inputSchema", sdk.json_schema(code_schema)),
              #(
                "execute",
                n.data(fn(arguments, options) {
                  run(n.string(arguments, "code"), options, arguments)
                }),
              ),
            ]),
          )
        let wrapped = case mode {
          router.Only -> []
          router.Gate ->
            list.map(natives, fn(entry) {
              let #(id, native) = entry
              #(
                id,
                n.with_fields(native, [
                  #(
                    "execute",
                    n.data(fn(arguments, options) {
                      run(router.single(id, arguments), options, arguments)
                    }),
                  ),
                ]),
              )
            })
          router.Off -> natives
        }
        n.object([#("eyg", eyg), ..wrapped])
      }
    }
  }
}

/// Minimal native source glue calls this before publishing task metadata.
pub fn notify(options: Dynamic, value: Dynamic) {
  let started = n.field(options, "eygStarted")
  let id = n.string(n.field(value, "metadata"), "sessionId")
  case foreign.is_function(started) && id != "" {
    True -> {
      let _ = foreign.apply(started, array.from_list([n.data(id)]))
      Nil
    }
    False -> Nil
  }
}

/// Keep the outer EYG program visible while native tools publish progress.
pub fn outer_args(options: Dynamic, fallback: Dynamic) {
  let arguments = n.field(options, "eygArguments")
  case foreign.is_undefined(arguments) {
    True -> fallback
    False -> arguments
  }
}
