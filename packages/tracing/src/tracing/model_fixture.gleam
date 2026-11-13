//// Scripted Ollama model and static debugger server used by the checked guides.

import gleam/dynamic/decode
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server
import simplifile

pub fn main() {
  let assert Ok(_) = start()
  io.println("Scripted model and debugger at http://127.0.0.1:7201")
}

pub fn start() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(response) = fetch.get_response()
  server.serve(
    bun,
    server.Options(7201, "127.0.0.1", fn(request) {
      use body <- promise.map(fetch.request_text(request))
      let assert Ok(body) = body
      let url = fetch.request_url(request)
      case string.contains(url, "/api/chat") {
        True -> {
          let assert Ok(response) =
            fetch.new_response(response, completion(body), 200, [
              #("content-type", "application/x-ndjson"),
            ])
          response
        }
        False -> static(response, url)
      }
    }),
  )
}

fn completion(body: String) -> String {
  let assert Ok(streaming) =
    json.parse(
      body,
      decode.optional_field("stream", False, decode.bool, decode.success),
    )
  let output_effect = case streaming {
    True -> "Print"
    False -> "StandardOut"
  }
  let message = {
    use role <- decode.field("role", decode.string)
    use content <- decode.optional_field(
      "content",
      "",
      decode.one_of(decode.string, [decode.success("")]),
    )
    decode.success(#(role, content))
  }
  let decoder = {
    use messages <- decode.field("messages", decode.list(message))
    decode.success(messages)
  }
  let assert Ok(messages) = json.parse(body, decoder)
  let assert Ok(last) = list.last(messages)
  let is_trace =
    list.any(messages, fn(m) {
      m.0 == "user" && string.contains(m.1, "Read your trace")
    })
  let calls = case last.0 {
    "tool" -> []
    _ -> [
      json.object([
        #(
          "function",
          json.object([
            #("name", json.string("run")),
            #(
              "arguments",
              json.object([
                #(
                  "code",
                  json.string(case is_trace {
                    True -> "perform Trace({})"
                    False ->
                      "let result = !int_add(2, 3) let _ = perform "
                      <> output_effect
                      <> "(!int_to_string(result)) result"
                  }),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    ]
  }
  let content = case calls, is_trace {
    [], True -> "Read the recorded trajectory."
    [], False -> "Computed 5."
    _, _ -> ""
  }
  json.object([
    #("model", json.string("local-scripted-demo")),
    #(
      "message",
      json.object([
        #("role", json.string("assistant")),
        #("content", json.string(content)),
        #("tool_calls", json.preprocessed_array(calls)),
      ]),
    ),
    #("done", json.bool(True)),
    #("prompt_eval_count", json.int(20)),
    #("eval_count", json.int(10)),
  ])
  |> json.to_string
  |> string.append("\n")
}

fn static(
  constructor: fetch.ResponseConstructor,
  url: String,
) -> fetch.Response {
  let path = string.replace(url, "http://127.0.0.1:7201", "")
  let path =
    string.split_once(path, "?")
    |> result.map(fn(pair) { pair.0 })
    |> result.unwrap(path)
  let root = "../website/dist"
  let path = case string.ends_with(path, "/") {
    True -> path <> "index.html"
    False -> path
  }
  let path = case simplifile.is_directory(root <> path) {
    Ok(True) -> path <> "/index.html"
    _ -> path
  }
  let mime =
    [
      #(".js", "application/javascript"),
      #(".css", "text/css"),
      #(".json", "application/json"),
      #(".svg", "image/svg+xml"),
      #(".png", "image/png"),
      #(".webp", "image/webp"),
      #(".webm", "video/webm"),
      #(".woff2", "font/woff2"),
    ]
    |> list.find_map(fn(pair) {
      case string.ends_with(path, pair.0) {
        True -> Ok(pair.1)
        False -> Error(Nil)
      }
    })
    |> result.unwrap("text/html")
  let #(body, status) = case simplifile.read_bits(root <> path) {
    Ok(bits) -> #(bits, 200)
    _ -> #(<<"not found">>, 404)
  }
  let assert Ok(response) =
    fetch.new_response_bits(constructor, body, status, [#("content-type", mime)])
  response
}
