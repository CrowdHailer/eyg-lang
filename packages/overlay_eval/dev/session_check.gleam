//// Check the CLI's real HTTP transport, cassette replay and report files.

import filepath
import gleam/dict
import gleam/dynamic/decode
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/string
import javascript/mutable_reference as cell
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/bun/subprocess
import plinthx/node/process
import simplifile

const code =
  "let sum = !fix((self, n, a, b, total) -> {
  match !int_compare(n, 0) {
    Eq(_) -> { total }
    | (_) -> { self(!int_subtract(n, 1), b, !int_add(a, b), !int_add(total, a)) }
  }
})
sum(20, 1, 1, 0)"

pub fn main() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let assert Ok(cwd) = simplifile.current_directory()
  let directory = "/tmp/eyg-roadmap-session-protocol"
  case simplifile.exists(directory, False) {
    Ok(True) -> {
      let assert Ok(_) = simplifile.delete(directory)
      Nil
    }
    _ -> Nil
  }
  let assert Ok(_) = simplifile.create_directory_all(directory)
  let count = cell.new(0)
  let assert Ok(fixture) = start(count)
  let env =
    process.env(host)
    |> dict.from_list
    |> dict.insert("OVERLAY_EVAL_OPENAI_ORIGIN", "http://127.0.0.1:7211")
    |> dict.to_list
  let checked =
    {
      use _ <- promise.await(
        run(bun, cwd, env, [
          "run",
          "suites/fibonacci.eyg",
          "--model",
          "openai-local:scripted",
          "--trials",
          "2",
          "--record",
          directory <> "/cassettes",
          "--out",
          directory <> "/recorded",
        ]),
      )
      assert cell.get(count) == 4
      use stopped <- promise.await(server.stop(fixture, True))
      let assert Ok(_) = stopped
      use _ <- promise.map(
        run(bun, cwd, env, [
          "run",
          "suites/fibonacci.eyg",
          "--model",
          "openai-local:scripted",
          "--trials",
          "2",
          "--replay",
          directory <> "/cassettes",
          "--out",
          directory <> "/replayed",
        ]),
      )
      assert cell.get(count) == 4
      let assert Ok(files) = simplifile.get_files(directory)
      assert list.count(files, string.ends_with(_, "/run.json")) == 2
      assert list.count(files, string.ends_with(_, "/summary.md")) == 2
      assert list.count(files, string.ends_with(_, "/trials/fibonacci-1.md"))
        == 2
      io.println(
        "PASS session CLI: actual EYG 17710, two trials, HTTP recording, strict offline replay and reports",
      )
      case simplifile.exists("evidence/session-protocol", False) {
        Ok(True) -> {
          let assert Ok(_) = simplifile.delete("evidence/session-protocol")
          Nil
        }
        _ -> Nil
      }
      let assert Ok(_) =
        simplifile.create_directory_all("evidence/session-protocol")
      list.each(files, fn(path) {
        case
          string.contains(path, "/recorded/")
          || string.contains(path, "/cassettes/")
        {
          False -> Nil
          True -> {
            let relative = string.drop_start(path, string.length(directory) + 1)
            let target = filepath.join("evidence/session-protocol", relative)
            let assert Ok(_) =
              simplifile.create_directory_all(filepath.directory_name(target))
            let assert Ok(bytes) = simplifile.read_bits(path)
            let assert Ok(_) = simplifile.write_bits(target, bytes)
            Nil
          }
        }
      })
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  use _ <- promise.map(server.stop(fixture, True))
  let assert Ok(_) = checked
}

fn run(bun, cwd, env, args) {
  let assert Ok(child) =
    subprocess.spawn(
      bun,
      subprocess.Options(
        ["gleam", "run", "-m", "overlay/eval", "--", ..args],
        cwd,
        env,
        "pipe",
        "pipe",
        "pipe",
      ),
    )
  let assert Ok(stdout) = subprocess.stdout(child)
  let assert Ok(stderr) = subprocess.stderr(child)
  use output <- promise.await(subprocess.readable_stream_to_text(bun, stdout))
  use errors <- promise.await(subprocess.readable_stream_to_text(bun, stderr))
  use status <- promise.map(subprocess.exited(child))
  let assert Ok(errors) = errors
  let assert Ok(0) = status as errors
  let assert Ok(output) = output
  assert string.contains(output, "Pass rate 100%") as output
  output
}

fn start(count) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(constructor) = fetch.get_response()
  server.serve(
    bun,
    server.Options(7211, "127.0.0.1", fn(request) {
      use body <- promise.map(fetch.request_text(request))
      let assert Ok(body) = body
      let assert Ok(roles) =
        json.parse(
          body,
          decode.field(
            "messages",
            decode.list(decode.field("role", decode.string, decode.success)),
            decode.success,
          ),
        )
      let assert Ok(last) = list.last(roles)
      let event = case last {
        "user" -> {
          assert !string.contains(body, "17710")
          let arguments =
            json.object([#("code", json.string(code))]) |> json.to_string
          json.object([
            #(
              "tool_calls",
              json.preprocessed_array([
                json.object([
                  #("index", json.int(0)),
                  #("id", json.string("run-fib")),
                  #(
                    "function",
                    json.object([
                      #("name", json.string("run")),
                      #("arguments", json.string(arguments)),
                    ]),
                  ),
                ]),
              ]),
            ),
          ])
        }
        "tool" -> {
          assert string.contains(body, "17710")
          json.object([#("content", json.string("The sum is 17710."))])
        }
        _ -> panic as "missing tool round trip"
      }
      cell.set(count, cell.get(count) + 1)
      let chunk =
        json.object([
          #(
            "choices",
            json.preprocessed_array([
              json.object([#("delta", event)]),
            ]),
          ),
        ])
        |> json.to_string
      let usage =
        "{\"choices\":[],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":3}}"
      let sse =
        "data: " <> chunk <> "\n\ndata: " <> usage <> "\n\ndata: [DONE]\n\n"
      let assert Ok(response) =
        fetch.new_response(constructor, sse, 200, [
          #("content-type", "text/event-stream"),
        ])
      response
    }),
  )
}
