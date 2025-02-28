import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/expression as r
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/runtime/break as old_break
import eyg/runtime/value as old_value
import gleam/dict
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import harness/effect
import harness/ffi/core
import harness/impl/http
import plinth/javascript/console
import plinth/node/readlines

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
}

pub fn run(source) {
  io.debug("needs to handle handlers extrinsic")

  let assert Ok(parser) = r.execute(source, [])
  let assert Ok(lisp) = cast.field("lisp", cast.any, parser)
  let assert Ok(parser) = cast.field("prompt", cast.any, lisp)
  let parser = fn(prompt) {
    fn(raw) {
      let args = [#(v.String(prompt), Nil), #(v.String(raw), Nil)]
      let assert Ok(v.Tagged(tag, value)) = r.call(parser, args)
      case tag {
        "Ok" ->
          result.replace_error(
            cast.field("value", cast.any, value),
            "no value field in parsed value",
          )
        "Error" -> {
          Error(old_value.debug(value))
        }
        _ -> panic as string.concat(["unexpected tag value: ", tag])
      }
    }
  }

  io.debug("needs to handle handlers handlers")

  let assert Ok(prog) = r.execute(source, [])
  let assert Ok(exec) = cast.field("exec", cast.any, prog)
  io.debug("needs to handle handlers handlers")

  let assert Error(#(break.UnhandledEffect("Prompt", prompt), _rev, env, k)) =
    r.call(exec, [#(v.unit(), Nil)])

  let assert v.String(prompt) = prompt

  let rl =
    readlines.create_interface(
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
  readlines.close(rl)
  promise.resolve(status)
}

fn read(rl, parser, env: state.Env(_), k, prompt) {
  use answer <- promise.await(readlines.question(rl, prompt))
  case parser(prompt)(answer) {
    Ok(term) -> {
      let assert v.LinkedList(cmd) = term
      let assert Ok(code) = core.language_to_expression(cmd)
      case code == ir.empty() {
        True -> promise.resolve(0)
        False -> {
          io.debug("needs to handle handlers")

          use ret <- promise.await(r.await(r.execute(code, env.scope)))
          let #(env, prompt) = case ret {
            Ok(value) -> {
              print(value)
              #(env, prompt)
            }
            Error(#(break.UnhandledEffect("Prompt", lift), _rev, env, _k)) -> {
              let assert v.String(prompt) = lift
              #(env, prompt)
            }
            Error(#(reason, _rev, _env, _k)) -> {
              console.log(
                string.concat([
                  "!! ",
                  old_break.reason_to_string(reason),
                  " at: ",
                ]),
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
        list.map(dict.to_list(fields), fn(field) {
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
              let value = old_value.debug(value)
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
    v.String("{\"headers\":[" <> _ as encoded) -> {
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
    _ -> io.println(old_value.debug(value))
  }
}

fn print_rows_and_headers(headers, rows) -> Nil {
  let rows =
    list.map(rows, fn(row) {
      let assert Ok(row) = list.strict_zip(headers, row)
      let row =
        list.map(row, fn(part) {
          let #(#(_, size), value) = part
          string.pad_end(value, size, " ")
          |> string.slice(0, size)
        })
        |> string.join(" | ")
      string.concat(["| ", row, " |"])
    })
  let headers =
    list.map(headers, fn(h) {
      let #(k, size) = h
      string.pad_end(k, size, " ")
    })
    |> string.join(" | ")
  let headers = string.concat(["| ", headers, " |"])
  io.println(headers)
  list.map(rows, io.println)
  Nil
}
