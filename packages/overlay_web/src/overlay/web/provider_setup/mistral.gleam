import overlay/llm/provider
import overlay/llm/provider/mistral

pub const id = "mistral"

pub const label = "Mistral"

pub const token_url = "https://console.mistral.ai/api-keys/"

pub fn default_model() {
  "mistral-small-latest"
}

pub fn models() {
  [
    #("mistral-small-latest", "Mistral Small"),
    #("mistral-medium-latest", "Mistral Medium"),
    #("mistral-large-latest", "Mistral Large"),
    #("codestral-latest", "Codestral"),
  ]
}

pub fn make_provider(api_key) {
  provider.Mistral(mistral.Config(api_key: api_key))
}
