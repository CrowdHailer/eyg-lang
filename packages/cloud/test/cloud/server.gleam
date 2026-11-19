//// A local HTTP server that records the requests it receives.
//// The first request to `/slow` is held until the test releases it.
//// It is also an llm, see `chat`.

import cloud/overlay
import eyg/hub/cache
import eyg/parser
import gleam/bytes_tree
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import mist
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama
import unixfs/mfs

pub type Server {
  Server(port: Int, received: Subject(Message))
}

pub type Message {
  Received(method: http.Method, path: String, reply: Subject(Int))
  Count(method: http.Method, path: String, reply: Subject(Int))
}

/// `arrived` receives a subject to release the held request.
pub fn start(arrived: Subject(Subject(Nil))) -> Server {
  let assert Ok(received) =
    actor.new(dict.new())
    |> actor.on_message(fn(counts, message) {
      case message {
        Received(method, path, reply) -> {
          let count = 1 + count(counts, method, path)
          process.send(reply, count)
          actor.continue(dict.insert(counts, #(method, path), count))
        }
        Count(method, path, reply) -> {
          process.send(reply, count(counts, method, path))
          actor.continue(counts)
        }
      }
    })
    |> actor.start
  let received = received.data
  // The system chooses a free port.
  let started = process.new_subject()
  let assert Ok(_) =
    mist.new(fn(request: request.Request(mist.Connection)) {
      let count =
        process.call(received, 1000, Received(request.method, request.path, _))
      case request.path, count {
        "/slow", 1 -> {
          let release = process.new_subject()
          process.send(arrived, release)
          let _ = process.receive(release, 60_000)
          Nil
        }
        _, _ -> Nil
      }
      // The server is also a hub with no releases, packages are added to the cache directly.
      case request.path {
        "/api/chat" -> {
          let assert Ok(read) = mist.read_body(request, 10_000_000)
          let #(content, calls) = chat(read.body)
          case json.parse_bits(read.body, decode.at(["stream"], decode.bool)) {
            Ok(True) -> stream(request, content, calls)
            _ -> respond(completion(content, calls, None))
          }
        }
        "/packages/pull" -> respond("{\"entries\":[]}")
        path -> respond(path)
      }
    })
    |> mist.bind("localhost")
    |> mist.port(0)
    |> mist.after_start(fn(port, _, _) { process.send(started, port) })
    |> mist.start
  let assert Ok(port) = process.receive(started, 1000)
  Server(port, received)
}

/// The server as an Ollama llm, it does what the last message from the user says.
/// A message `run:` followed by code blocks separated by `---` is a tool call for each block, one at a time.
/// After the last call it answers with the result of that call.
/// A message saying its changes were rejected is not an instruction, the next block is run.
/// Any other message is answered with itself and the number of messages from the user in the chat.
pub fn llm(server: Server) {
  provider.Llm(provider.Ollama(ollama.Config(origin(server), None)), "test")
}

fn chat(body) {
  let message = {
    use role <- decode.field("role", decode.string)
    use content <- decode.field("content", decode.string)
    decode.success(#(role, content))
  }
  let assert Ok(messages) =
    json.parse_bits(body, decode.at(["messages"], decode.list(message)))
  // Messages telling the llm its changes were rejected are not instructions.
  let instruction = fn(m: #(String, String)) {
    m.0 == "user" && !string.starts_with(m.1, overlay.rejected_prefix)
  }
  let #(results, earlier) =
    list.reverse(messages) |> list.split_while(fn(m) { !instruction(m) })
  let assert [#(_, last), ..] = earlier
  let results = list.filter(results, fn(m) { m.0 == "tool" })
  let reply = fn(content, calls) { #(content, calls) }
  case last {
    "run:" <> blocks ->
      case list.drop(string.split(blocks, "\n---\n"), list.length(results)) {
        [code, ..] -> {
          let arguments = json.object([#("code", json.string(code))])
          let function =
            json.object([
              #("name", json.string("run")),
              #("arguments", arguments),
            ])
          reply("", [json.object([#("function", function)])])
        }
        [] -> {
          let assert [#(_, result), ..] = results
          reply(result, [])
        }
      }
    message -> {
      let count = list.count(messages, fn(m) { m.0 == "user" })
      reply(message <> " #" <> int.to_string(count), [])
    }
  }
}

fn respond(body) {
  response.new(200)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn completion(content, calls, done) {
  thought("", content, calls, done)
}

fn thought(thinking, content, calls, done) {
  json.object([
    #(
      "message",
      json.object([
        #("thinking", json.string(thinking)),
        #("content", json.string(content)),
        #("tool_calls", json.preprocessed_array(calls)),
      ]),
    ),
    ..case done {
      Some(done) -> [#("done", json.bool(done))]
      None -> []
    }
  ])
  |> json.to_string
}

// A streamed completion is a line of JSON for each few characters of its content, then a line with the tool calls.
// The reply to a message that starts with `slow:` pauses after each line, so the lines arrive one at a time.
// The reply to a message that starts with `think:` thinks about the message first.
fn stream(request, content, calls) {
  let pieces = fn(text) {
    string.to_graphemes(text) |> list.sized_chunk(4) |> list.map(string.concat)
  }
  let thinking = case string.starts_with(content, "think:") {
    True ->
      pieces("Thinking about " <> content)
      |> list.map(fn(piece) { thought(piece, "", [], Some(False)) })
    False -> []
  }
  let lines =
    list.flatten([
      thinking,
      pieces(content)
        |> list.map(fn(piece) { completion(piece, [], Some(False)) }),
      [completion("", calls, Some(True))],
    ])
  mist.chunked(
    request,
    response.new(200),
    fn(subject) {
      list.each(lines, fn(line) { process.send(subject, Ok(line <> "\n")) })
      process.send(subject, Error(Nil))
      string.starts_with(content, "slow:")
    },
    fn(slow, line, connection) {
      case line {
        Ok(line) -> {
          let assert Ok(Nil) = mist.send_chunk(connection, <<line:utf8>>)
          case slow {
            True -> process.sleep(20)
            False -> Nil
          }
          mist.chunk_continue(slow)
        }
        Error(Nil) -> mist.chunk_stop()
      }
    },
  )
}

fn count(counts, method, path) {
  case dict.get(counts, #(method, path)) {
    Ok(count) -> count
    Error(Nil) -> 0
  }
}

/// The number of requests received with this method and path.
pub fn count_requests(server: Server, method, path) {
  process.call(server.received, 1000, Count(method, path, _))
}

/// EYG code that makes a request to the server.
pub fn fetch(server: Server, method, path) {
  "perform Fetch({method: "
  <> method
  <> "({}), scheme: HTTP({}), host: \"localhost\", port: Some("
  <> int.to_string(server.port)
  <> "), path: \""
  <> path
  <> "\", query: None({}), headers: [], body: !string_to_binary(\"\")})"
}

/// The server as the origin of the hub.
pub fn origin(server: Server) {
  let assert Ok(origin) =
    origin.from_string_strict("http://localhost:" <> int.to_string(server.port))
  origin
}

/// Add a module to the cache as the latest release of a package.
pub fn release(
  cache: cache.Cache(#(Int, Int)),
  name: String,
  code: String,
) -> cache.Cache(#(Int, Int)) {
  let assert Ok(source) = parser.all_from_string(code)
  let module = mfs.identify(mfs.File(<<code:utf8>>)).cid
  let #(cache, _) = cache.fetch_module_completed(cache, module, Ok(source))
  let entry = cache.Entry(1, module, 1, 1, module)
  cache.Cache(..cache, packages: dict.insert(cache.packages, name, entry))
}
