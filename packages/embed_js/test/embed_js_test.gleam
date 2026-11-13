import embed_js
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

fn parse(text: String) -> dynamic.Dynamic {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

pub fn a_session_runs_code_with_json_effects_test() {
  let assert Ok(session) =
    embed_js.create(
      parse("{\"Echo\": {\"lift\": \"string\", \"lower\": \"string\"}}"),
      "",
    )
  let embed_js.Run(json:, error:, ..) =
    embed_js.run(session, "perform Echo(\"hi\")", fn(label, input) {
      let assert "Echo" = label
      input
    })
  assert #(json, error) == #(Some("\"hi\""), None)
}

pub fn effects_must_be_described_test() {
  let assert Error(_) = embed_js.create(parse("{\"Echo\": {}}"), "")
  let assert Error(_) = embed_js.create(parse("{}"), "not an origin")
}
