import eyg/cli/helpers
import eyg/cli/overlay
import loam/source
import loam/system

pub fn load_policy_test() {
  let input =
    source.Code(
      "{
  llm: Ollama({origin: \"https://ollama.com\", api_key: Some(\"key_ollama\")})
}",
    )
  let assert system.Done(return) = overlay.execute(input, helpers.config)
  echo return
  todo
}
