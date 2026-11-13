//// Verify the compiled CLI's Chat Completions protocol against real HTTP.

import filepath
import glasshouse/archive
import glasshouse/rerun
import glasshouse/session
import gleam/dict
import gleam/dynamic/decode
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import javascript/mutable_reference as cell
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/bun/subprocess
import plinthx/node/process
import simplifile

pub fn main() {
  let assert Ok(_) = simplifile.create_directory_all("recordings")
  let assert Ok(bun) = runtime.get()
  let assert Ok(host) = process.get()
  let env = process.env(host) |> dict.from_list
  let binary =
    dict.get(env, "EYG_BIN") |> result.unwrap("../gleam_cli/dist/eyg")
  let assert Ok(cwd) = simplifile.current_directory()
  let directory = filepath.join(cwd, ".recordings/openai")
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
  let checked =
    {
      let env = env |> dict.insert("EYG_TRACE_DIR", directory) |> dict.to_list
      let assert Ok(child) =
        subprocess.spawn_with_input(
          bun,
          subprocess.Options(
            [binary, "overlay", "fixtures/openai.eyg"],
            ".",
            env,
            "pipe",
            "pipe",
            "pipe",
          ),
          <<"calculate\n\n">>,
        )
      let assert Ok(stdout) = subprocess.stdout(child)
      let assert Ok(stderr) = subprocess.stderr(child)
      use output <- promise.await(subprocess.readable_stream_to_text(
        bun,
        stdout,
      ))
      use errors <- promise.await(subprocess.readable_stream_to_text(
        bun,
        stderr,
      ))
      use status <- promise.map(subprocess.exited(child))
      let assert Ok(errors) = errors
      let assert Ok(0) = status as errors
      let assert Ok(output) = output
      assert string.contains(output, "Computed 42.") as output
      assert cell.get(count) == 2
      let assert Ok(files) = simplifile.read_directory(directory)
      let assert [file] = files
      let assert Ok(text) = simplifile.read(filepath.join(directory, file))
      let assert Ok(saved) = archive.from_string(text)
      assert archive.missing(saved) == []
      let assert [first, second] = session.generations(saved.session)
      assert first.usage == session.Usage(7, 3)
      assert second.usage == session.Usage(7, 3)
      assert first.error == None && second.error == None
      assert list.all(rerun.session(saved.session, saved.store), fn(report) {
        report.problem == None
      })
      let assert Ok(_) =
        simplifile.write("recordings/openai-protocol.json", text)
      io.println(
        "PASS real HTTP Chat Completions: auth, headers, fragmented tools, usage, archive closure and replay",
      )
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use checked <- promise.await(checked)
  use stopped <- promise.map(server.stop(fixture, True))
  let assert Ok(_) = stopped
  let assert Ok(_) = checked
}

fn start(count) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(constructor) = fetch.get_response()
  server.serve(
    bun,
    server.Options(7209, "127.0.0.1", fn(request) {
      use body <- promise.map(fetch.request_text(request))
      let assert Ok(body) = body
      assert fetch.request_method(request) == "POST"
      assert string.ends_with(
        fetch.request_url(request),
        "/v1/chat/completions",
      )
      assert fetch.request_header(request, "authorization")
        == Some("Bearer fixture-key")
      assert fetch.request_header(request, "x-fixture") == Some("checked")
      let _ = cell.update(count, fn(value) { value + 1 })
      let assert Ok(stream) =
        json.parse(body, decode.field("stream", decode.bool, decode.success))
      assert stream
      let assert Ok(include_usage) =
        json.parse(
          body,
          decode.field(
            "stream_options",
            decode.field("include_usage", decode.bool, decode.success),
            decode.success,
          ),
        )
      assert include_usage
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
      let events = case last {
        "user" -> [
          "{\"choices\":[{\"delta\":{\"content\":\"Calculating.\",\"tool_calls\":[{\"index\":0,\"id\":\"run-42\",\"function\":{\"name\":\"run\",\"arguments\":\"{\\\"co\"}}]}}]}",
          "{\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"de\\\":\\\"!int_add(20, 22)\\\"}\"}}]}}]}",
        ]
        "tool" -> ["{\"choices\":[{\"delta\":{\"content\":\"Computed 42.\"}}]}"]
        _ -> panic as "The expected tool round trip did not occur"
      }
      let usage =
        "{\"choices\":[],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":3}}"
      let sse =
        list.append(events, [usage, "[DONE]"])
        |> list.map(fn(event) { "data: " <> event <> "\r\n\r\n" })
        |> string.concat
      let assert Ok(response) =
        fetch.new_response(constructor, sse, 200, [
          #("content-type", "text/event-stream"),
        ])
      response
    }),
  )
}
