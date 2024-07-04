import eyg/runtime/break
import eyg/runtime/cast
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eygir/annotated as e
import gleam/dict
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/javascript/array.{type Array}
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import harness/effect
import harness/fetch
import harness/ffi/core
import harness/impl/http
import harness/stdlib
import plinth/javascript/console

pub type Interface

// TODO readlines bindings in readlines project or in plinth as part of node
@external(javascript, "../plinth_readlines_ffi.js", "createInterface")
pub fn create_interface(
  completer: fn(String) -> #(Array(String), String),
  history: Array(String),
) -> Interface

@external(javascript, "../plinth_readlines_ffi.js", "question")
pub fn question(interface: Interface, prompt: String) -> promise.Promise(String)

@external(javascript, "../plinth_readlines_ffi.js", "close")
pub fn close(interface: Interface) -> promise.Promise(String)

fn handlers() {
  effect.init()
  |> effect.extend("Log", effect.debug_logger())
  |> effect.extend("Open", effect.open())
  |> effect.extend("Await", effect.await())
  |> effect.extend("Wait", effect.wait())
  |> effect.extend("Serve", http.serve())
  |> effect.extend("StopServer", http.stop_server())
  |> effect.extend("Receive", http.receive())
  |> effect.extend("File_Write", effect.file_write())
  |> effect.extend("File_Read", effect.file_read())
  |> effect.extend("Read_Source", effect.read_source())
  |> effect.extend("LoadDB", effect.load_db())
  |> effect.extend("QueryDB", effect.query_db())
  |> effect.extend("Zip", effect.zip())
}

pub fn run(source) {
  let env =
    state.Env(scope: [], references: dict.new(), builtins: stdlib.lib().1)
  let assert Ok(parser) = r.execute(source, env, handlers().1)
  let assert Ok(lisp) = cast.field("lisp", cast.any, parser)
  let assert Ok(parser) = cast.field("prompt", cast.any, lisp)
  let parser = fn(prompt) {
    fn(raw) {
      let k = dict.new()
      let args = [#(v.Str(prompt), Nil), #(v.Str(raw), Nil)]
      let assert Ok(v.Tagged(tag, value)) = r.resume(parser, args, env, k)
      case tag {
        "Ok" ->
          result.replace_error(
            cast.field("value", cast.any, value),
            "no value field in parsed value",
          )
        "Error" -> {
          Error(v.debug(value))
        }
        _ -> panic as string.concat(["unexpected tag value: ", tag])
      }
    }
  }

  let assert Ok(prog) = r.execute(source, env, handlers().1)
  let assert Ok(exec) = cast.field("exec", cast.any, prog)
  let assert Error(#(break.UnhandledEffect("Prompt", prompt), _rev, env, k)) =
    r.resume(exec, [#(v.unit, Nil)], env, handlers().1)

  let assert v.Str(prompt) = prompt

  let rl =
    create_interface(
      fn(_) { #(array.from_list([]), "") },
      array.from_list([
        "(.test (source {}) {})",
        "(let s (source {}) (s.projects.inference.test {}))",
        "let stop_editor (projects.website.local 8080)",
        "(let s (source {}) (s.projects.explain.spike {}))",
        "let me (personal {})",
        "let stop ((let s (source {}) s.projects.explain.local) 5000)",
        "(let p (.projects (source {})) legit.run p.recipe.tests)",
      ]),
    )
  use status <- promise.await(read(rl, parser, env, k, prompt))
  close(rl)
  promise.resolve(status)
}

fn read(rl, parser, env, k, prompt) {
  use answer <- promise.await(question(rl, prompt))
  case parser(prompt)(answer) {
    Ok(term) -> {
      let assert v.LinkedList(cmd) = term
      let assert Ok(code) = core.language_to_expression(cmd)
      case code == #(e.Empty, Nil) {
        True -> promise.resolve(0)
        False -> {
          use ret <- promise.await(r.await(r.execute(code, env, handlers().1)))
          let #(env, prompt) = case ret {
            Ok(value) -> {
              print(value)
              #(env, prompt)
            }
            Error(#(break.UnhandledEffect("Prompt", lift), _rev, env, _k)) -> {
              let assert v.Str(prompt) = lift
              #(env, prompt)
            }
            Error(#(reason, rev, _env, _k)) -> {
              console.log(
                string.concat(["!! ", break.reason_to_string(reason), " at: "]),
              )
              // TODO add path
              // path_to_string(list.reverse(rev)),
              #(env, prompt)
            }
          }
          read(rl, parser, env, k, prompt)
        }
      }
    }
    Error(reason) -> {
      io.debug(string.append("failed to parse input ", reason))
      read(rl, parser, env, k, prompt)
    }
  }
}

pub fn path_to_string(path) {
  list.map(path, int.to_string)
  |> string.join(",")
}

fn print(value) {
  case value {
    v.LinkedList([v.Record(fields), ..] as records) -> {
      let headers =
        list.map(fields, fn(field) {
          let #(key, _value) = field
          #(key, string.length(key))
        })

      let #(headers, rows_rev) =
        list.fold(records, #(headers, []), fn(acc, rec) {
          let #(headers, rows_rev) = acc
          let #(reversed_col, headers) =
            list.map_fold(headers, [], fn(acc, header) {
              let #(key, size) = header
              let assert Ok(value) = cast.field(key, cast.any, rec)
              let value = v.debug(value)
              let size = int.max(size, string.length(value))
              let size = int.min(20, size)
              let header = #(key, size)
              let acc = [value, ..acc]
              #(acc, header)
            })
          let rows_rev = [list.reverse(reversed_col), ..rows_rev]
          #(headers, rows_rev)
        })

      let rows = list.reverse(rows_rev)
      print_rows_and_headers(headers, rows)
    }
    v.Str("{\"headers\":[" <> _ as encoded) -> {
      let decoder =
        dynamic.decode2(
          fn(a, b) { #(a, b) },
          dynamic.field("headers", dynamic.list(dynamic.string)),
          dynamic.field("rows", dynamic.list(dynamic.list(Ok))),
        )
      // TODO move to cozo lib
      let assert Ok(#(headers, rows)) = json.decode(encoded, decoder)
      let headers = list.map(headers, fn(h) { #(h, string.length(h)) })

      let #(headers, rows_rev) =
        list.fold(rows, #(headers, []), fn(acc, row) {
          let #(headers, rows_rev) = acc
          let assert Ok(row) = list.strict_zip(headers, row)
          let #(headers, row) =
            list.map(row, fn(r) {
              let #(#(key, size), value) = r
              let value = string.inspect(value)
              let size = int.max(size, string.length(value))
              let size = int.min(20, size)
              #(#(key, size), value)
            })
            |> list.unzip()
          #(headers, [row, ..rows_rev])
        })
      let rows = list.reverse(rows_rev)
      print_rows_and_headers(headers, rows)
    }
    _ -> io.println(v.debug(value))
  }
}

fn print_rows_and_headers(headers, rows) -> Nil {
  let rows =
    list.map(rows, fn(row) {
      let assert Ok(row) = list.strict_zip(headers, row)
      let row =
        list.map(row, fn(part) {
          let #(#(_, size), value) = part
          string.pad_right(value, size, " ")
          |> string.slice(0, size)
        })
        |> string.join(" | ")
      string.concat(["| ", row, " |"])
    })
  let headers =
    list.map(headers, fn(h) {
      let #(k, size) = h
      string.pad_right(k, size, " ")
    })
    |> string.join(" | ")
  let headers = string.concat(["| ", headers, " |"])
  io.println(headers)
  list.map(rows, io.println)
  Nil
}
