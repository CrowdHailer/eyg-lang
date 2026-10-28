//// A native bundle host: every value crossing the SDK boundary is plain data.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import javascript/mutable_reference as reference
import plinthx/javascript/foreign
import plinthx/javascript/module
import todomvc/tasks.{type Tasks}

pub opaque type Shell {
  Shell(Dynamic)
}

pub type Outcome {
  Returned(Dynamic)
  Failed(String)
}

pub type Run {
  Run(shell: Shell, tasks: Tasks, outcome: Outcome, output: String)
}

fn plain(value) {
  let assert Ok(value) = json.parse(json.to_string(value), decode.dynamic)
  value
}

fn object(fields) {
  foreign.object(array.from_list(fields))
}

fn invoke(target, method, arguments) {
  foreign.apply(foreign.property(target, method), array.from_list(arguments))
}

pub fn start(library: String, hub: String) {
  start_at(hub <> "/eyg.mjs", library, hub)
}

/// A URL or local module path lets browser and Node hosts consume the same file.
pub fn start_at(api: String, library: String, hub: String) {
  {
    use loaded <- promise.await(module.load(api))
    let assert Ok(loaded) = loaded
    let assert Ok(effects) = json.parse(effects, decode.dynamic)
    let options =
      object([
        #("effects", effects),
        #("hub", dynamic.string(hub)),
        #("modules", object([#("todos", dynamic.string(library))])),
      ])
    invoke(loaded, "createShell", [options])
    |> foreign.to_promise
    |> promise.map(fn(shell) { Ok(Shell(shell)) })
  }
  |> promise.rescue(fn(_) { Error("Unable to create the native shell") })
}

const effects =
  "{
  \"ListTasks\": {\"lift\":\"unit\",\"lower\":{\"list\":{\"record\":{\"id\":\"integer\",\"title\":\"string\",\"completed\":\"boolean\"}}}},
  \"CreateTask\": {\"lift\":\"string\",\"lower\":\"integer\"},
  \"RenameTask\": {\"lift\":{\"record\":{\"id\":\"integer\",\"title\":\"string\"}},\"lower\":{\"result\":{\"ok\":\"unit\",\"error\":{\"union\":{\"NotFound\":\"unit\"}}}}},
  \"SetCompleted\": {\"lift\":{\"record\":{\"id\":\"integer\",\"completed\":\"boolean\"}},\"lower\":{\"result\":{\"ok\":\"unit\",\"error\":{\"union\":{\"NotFound\":\"unit\"}}}}},
  \"Print\": {\"lift\":\"string\",\"lower\":\"unit\"}
}"

pub fn text(shell: Shell, name: String, field: String) {
  let Shell(shell) = shell
  invoke(shell, "text", [dynamic.string(name), dynamic.string(field)])
  |> decode.run(decode.string)
  |> result.unwrap("")
}

pub fn run(shell: Shell, initial: Tasks, code: String) -> Run {
  let Shell(native) = shell
  let current = reference.new(initial)
  let printed = reference.new([])
  let handlers =
    object([
      #(
        "ListTasks",
        foreign.to_dynamic(fn(_) {
          json.array(tasks.all(reference.get(current)), fn(task) {
            json.object([
              #("id", json.int(task.id)),
              #("title", json.string(task.title)),
              #("completed", json.bool(task.completed)),
            ])
          })
          |> plain
        }),
      ),
      #(
        "CreateTask",
        foreign.to_dynamic(fn(input) {
          let assert Ok(title) = decode.run(input, decode.string)
          let #(updated, id) = tasks.create(reference.get(current), title)
          reference.set(current, updated)
          dynamic.int(id)
        }),
      ),
      #(
        "RenameTask",
        foreign.to_dynamic(fn(input) {
          let assert Ok(#(id, title)) =
            decode.run(input, {
              use id <- decode.field("id", decode.int)
              use title <- decode.field("title", decode.string)
              decode.success(#(id, title))
            })
          found(current, tasks.rename(reference.get(current), id, title))
        }),
      ),
      #(
        "SetCompleted",
        foreign.to_dynamic(fn(input) {
          let assert Ok(#(id, completed)) =
            decode.run(input, {
              use id <- decode.field("id", decode.int)
              use completed <- decode.field("completed", decode.bool)
              decode.success(#(id, completed))
            })
          found(
            current,
            tasks.set_completed(reference.get(current), id, completed),
          )
        }),
      ),
      #(
        "Print",
        foreign.to_dynamic(fn(input) {
          let assert Ok(line) = decode.run(input, decode.string)
          reference.set(printed, [line, ..reference.get(printed)])
          object([])
        }),
      ),
    ])
  let response = invoke(native, "run", [dynamic.string(code), handlers])
  let assert Ok(#(error, display)) =
    decode.run(response, {
      use error <- decode.optional_field(
        "error",
        None,
        decode.optional(decode.string),
      )
      use display <- decode.optional_field("display", "{}", decode.string)
      decode.success(#(error, display))
    })
  let outcome = case error {
    Some(reason) -> Failed(reason)
    None -> Returned(foreign.property(response, "value"))
  }
  let output = case error {
    Some(reason) -> reason
    None -> display
  }
  let output =
    list.reverse(reference.get(printed)) |> list.append([output]) |> join_lines
  Run(shell:, tasks: reference.get(current), outcome:, output:)
}

fn join_lines(lines) {
  case lines {
    [] -> ""
    [line] -> line
    [line, ..rest] -> line <> "\n" <> join_lines(rest)
  }
}

fn found(current, changed) {
  case changed {
    Ok(updated) -> {
      reference.set(current, updated)
      plain(json.object([#("$", json.string("Ok"))]))
    }
    Error(Nil) ->
      plain(
        json.object([
          #("$", json.string("Error")),
          #("value", json.object([#("$", json.string("NotFound"))])),
        ]),
      )
  }
}

pub fn report(run: Run) {
  run.output
}
