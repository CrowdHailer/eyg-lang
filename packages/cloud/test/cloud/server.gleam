//// A local HTTP server that records the requests it receives.
//// The first request to `/slow` is held until the test releases it.
//// It is also an llm, see `chat`.

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
import gleam/option.{None}
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
      let body = case request.path {
        "/packages/pull" -> "{\"entries\":[]}"
        "/api/chat" -> {
          let assert Ok(request) = mist.read_body(request, 10_000_000)
          chat(request.body)
        }
        path -> path
      }
      response.new(200)
      |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
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
  let #(results, earlier) =
    list.reverse(messages) |> list.split_while(fn(m) { m.0 != "user" })
  let assert [#(_, last), ..] = earlier
  let results = list.filter(results, fn(m) { m.0 == "tool" })
  let reply = fn(content, calls) {
    json.object([
      #(
        "message",
        json.object([
          #("content", json.string(content)),
          #("tool_calls", json.preprocessed_array(calls)),
        ]),
      ),
    ])
    |> json.to_string
  }
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
