//// Scripted model for the artifact guide; uses a real hub for sharing.

import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import plinthx/browser/fetch
import plinthx/bun/runtime
import plinthx/bun/server

pub fn start() {
  start_with([])
}

pub fn start_with(codes: List(#(String, String))) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(response) = fetch.get_response()
  server.serve(
    bun,
    server.Options(7201, "127.0.0.1", fn(request) {
      use body <- promise.map(fetch.request_text(request))
      let assert Ok(body) = body
      let assert Ok(response) =
        fetch.new_response(response, completion(body, codes), 200, [
          #("content-type", "application/x-ndjson"),
        ])
      response
    }),
  )
}

fn completion(body, codes: List(#(String, String))) {
  let message = {
    use role <- decode.field("role", decode.string)
    use content <- decode.optional_field("content", "", decode.string)
    decode.success(#(role, content))
  }
  let assert Ok(messages) =
    json.parse(
      body,
      decode.field("messages", decode.list(message), decode.success),
    )
  let assert Ok(last) = list.last(messages)
  let prompt =
    list.filter(messages, fn(m) { m.0 == "user" })
    |> list.last
    |> result.map(fn(m) { m.1 })
    |> result.unwrap("")
  let revise = string.contains(prompt, "Revise")
  let checked = list.any(codes, fn(entry) { string.contains(prompt, entry.0) })
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
                  json.string(
                    list.find_map(codes, fn(entry) {
                      case string.contains(prompt, entry.0) {
                        True -> Ok(entry.1)
                        False -> Error(Nil)
                      }
                    })
                    |> result.unwrap(code(revise)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    ]
  }
  json.object([
    #("model", json.string("scripted-artifact-guide")),
    #(
      "message",
      json.object([
        #("role", json.string("assistant")),
        #(
          "content",
          json.string(case calls {
            [] ->
              case checked, revise {
                True, _ -> "Checked " <> prompt <> "."
                False, True -> "Revised the notebook and checked its preview."
                False, False -> "Created the notebook and checked its preview."
              }
            _ -> ""
          }),
        ),
        #("tool_calls", json.preprocessed_array(calls)),
      ]),
    ),
    #("done", json.bool(True)),
    #("prompt_eval_count", json.int(40)),
    #("eval_count", json.int(20)),
  ])
  |> json.to_string
  |> string.append("\n")
}

pub fn code(revise) {
  let html =
    "<!doctype html><html><head><link rel=\"stylesheet\" href=\"style.css\"></head><body><h1>Field notebook</h1><p>"
    <> case revise {
      True -> "Revision two: observations ready to share."
      False -> "Revision one: prepare your observations."
    }
    <> "</p><label>Topic <input id=\"topic\" placeholder=\"Observation topic\"></label><label><input type=\"checkbox\" id=\"reviewed\">Reviewed</label><details><summary>Checklist</summary><p>Record location, time and weather.</p></details><button>Save locally</button></body></html>"
  let css =
    "html{font:18px system-ui;color:#243a31;background:#f5f2e9}body{padding:1.5rem}label{display:block;margin:1rem 0}input{font:inherit;padding:.3rem}summary,button{cursor:pointer}button{padding:.5rem 1rem;background:#376c56;color:white;border:0;border-radius:.3rem}"
  let quote = fn(text) { json.to_string(json.string(text)) }
  let request = fn(locator, action) {
    "perform Puppet({page: Artifact(\"notebook\"), locator: "
    <> locator
    <> ", action: "
    <> action
    <> ", timeout: 3000})"
  }
  "let _ = perform Artifact({name: \"notebook\", bundle: [{path: \"index.html\", media_type: \"text/html\", content: !string_to_binary("
  <> quote(html)
  <> ")}, {path: \"style.css\", media_type: \"text/css\", content: !string_to_binary("
  <> quote(css)
  <> ")}]})\n"
  <> "let _ = perform Show({item: Artifact(\"notebook\"), origin: {x: 0, y: 0}, size: {x: 1000, y: 1000}})\n"
  <> "let _ = "
  <> request("[Label(\"Topic\")]", "Fill(\"Coastal birds\")")
  <> "\n"
  <> "let _ = "
  <> request(
    "[Role({role: \"checkbox\", name: \"Reviewed\"})]",
    "SetChecked(True({}))",
  )
  <> "\n"
  <> "let _ = "
  <> request("[Text(\"Checklist\")]", "Click({})")
  <> "\n"
  <> "let _ = "
  <> request("[Css(\"#topic\")]", "Expect(ToHaveValue(\"Coastal birds\"))")
  <> "\n"
  <> request("[]", "Screenshot({})")
}
