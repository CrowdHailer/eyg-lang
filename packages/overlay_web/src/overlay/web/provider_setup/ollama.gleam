import gleam/option.{Some}
import overlay/llm/provider
import overlay/llm/provider/ollama

pub const id = "ollama"

pub const label = "Ollama Cloud"

pub const token_url = "https://ollama.com/settings/keys"

pub fn default_model() {
  "gemma4:31b"
}

pub fn models() {
  [
    #("gemma4:31b", "Gemma 4 31B"),
    #("gpt-oss:120b", "GPT-OSS 120B"),
    #("kimi-k2.6", "Kimi K2.6"),
    #("mistral-large-3:675b", "Mistral Large 3"),
  ]
}

pub fn make_provider(api_key, origin) {
  provider.Ollama(ollama.Config(origin: origin, api_key: Some(api_key)))
}
