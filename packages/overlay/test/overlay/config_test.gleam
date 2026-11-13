import eyg/analysis/inference/levels_j/contextual as infer
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/parser
import gleam/dict
import gleam/option.{None, Some}
import ogre/origin
import overlay/config
import overlay/llm/provider
import overlay/llm/provider/bedrock
import overlay/llm/provider/codex
import overlay/llm/provider/mistral
import overlay/llm/provider/ollama
import overlay/llm/provider/openai
import overlay/llm/sigv4

fn record(fields) -> state.Value(Nil) {
  v.Record(dict.from_list(fields))
}

fn config(provider) {
  record([
    #("llm", record([#("provider", provider), #("model", v.String("m"))])),
    #("policy", record([])),
    #("context", record([])),
  ])
}

fn provider(value) {
  let assert Ok(config.Config(llm: provider.Llm(provider:, ..), ..)) =
    config.cast(config(value), [])
  provider
}

pub fn ollama_test() {
  let value =
    v.Tagged(
      "Ollama",
      record([
        #("origin", v.String("http://localhost:11434")),
        #("api_key", v.Tagged("None", record([]))),
      ]),
    )
  assert provider(value) == provider.Ollama(ollama.local())
}

pub fn openai_test() {
  let value =
    v.Tagged(
      "OpenAI",
      record([
        #("origin", v.String("https://openrouter.ai")),
        #("api_key", v.Tagged("Some", v.String("k"))),
        #("path", v.String("/api/v1/chat/completions")),
        #(
          "headers",
          v.LinkedList([
            record([#("key", v.String("x-title")), #("value", v.String("o"))]),
          ]),
        ),
      ]),
    )
  assert provider(value)
    == provider.OpenAI(
      openai.Config(
        origin: origin.https("openrouter.ai"),
        path: "/api/v1/chat/completions",
        api_key: Some("k"),
        headers: [#("x-title", "o")],
      ),
    )
}

pub fn openai_config_type_checks_test() {
  let code =
    "{
      llm: {
        provider: OpenAI({
          origin: \"https://openrouter.ai\",
          api_key: Some(\"k\"),
          path: \"/api/v1/chat/completions\",
          headers: [{key: \"x-title\", value: \"o\"}]
        }),
        model: \"m\"
      },
      policy: {},
      context: {}
    }"
  let assert Ok(source) = parser.all_from_string(code)
  let context = infer.pure()
  let #(expected, _context, bindings) =
    config.type_([], context.level, context.bindings)
  let assert infer.Done(analysis) =
    infer.Context(..context, bindings:)
    |> infer.with_expected_type(expected)
    |> infer.check(source)
  assert [] == infer.all_errors(analysis)
}

pub fn mistral_test() {
  let value = v.Tagged("Mistral", record([#("api_key", v.String("k"))]))
  assert provider(value) == provider.Mistral(mistral.Config("k"))
}

pub fn bedrock_test() {
  let value =
    v.Tagged(
      "Bedrock",
      record([
        #("region", v.String("us-east-1")),
        #("access_key_id", v.String("AKID")),
        #("secret_access_key", v.String("secret")),
        #("session_token", v.Tagged("None", record([]))),
      ]),
    )
  assert provider(value)
    == provider.Bedrock(bedrock.Config(
      region: "us-east-1",
      credentials: sigv4.Credentials(
        access_key_id: "AKID",
        secret_access_key: "secret",
        session_token: None,
      ),
    ))
}

pub fn bedrock_session_token_test() {
  let value =
    v.Tagged(
      "Bedrock",
      record([
        #("region", v.String("us-east-1")),
        #("access_key_id", v.String("AKID")),
        #("secret_access_key", v.String("secret")),
        #("session_token", v.Tagged("Some", v.String("token"))),
      ]),
    )
  let assert provider.Bedrock(bedrock.Config(credentials:, ..)) =
    provider(value)
  assert credentials.session_token == Some("token")
}

pub fn codex_test() {
  let value =
    v.Tagged(
      "Codex",
      record([
        #("access_token", v.String("token")),
        #("account_id", v.String("account")),
      ]),
    )
  assert provider(value) == provider.Codex(codex.Config("token", "account"))
}
