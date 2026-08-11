import gleam/option.{type Option, None, Some}
import gleam/string
import overlay/llm/provider
import overlay/web/provider_setup/mistral
import overlay/web/provider_setup/ollama
import pal/system

const provider_key = "overlay.llm.provider"

const model_key = "overlay.llm.model"

const api_key_key = "overlay.llm.api_key"

pub type ProviderChoice {
  Ollama
  Mistral
}

pub type State {
  State(
    provider: Option(ProviderChoice),
    model_name: String,
    api_key: String,
    configured: Bool,
    active_provider: Option(ProviderChoice),
    active_model: String,
    settings_open: Bool,
    error: Option(String),
    restoring: Bool,
  )
}

pub type Message {
  ToggleSettings
  ProviderSelected(String)
  ModelSelected(String)
  ApiKeyUpdated(String)
  SaveSettings
  SessionSettingsLoaded(provider: String, model: String, api_key: String)
  SessionSettingsStored
}

pub fn new() -> State {
  State(
    provider: None,
    model_name: "",
    api_key: "",
    configured: False,
    active_provider: None,
    active_model: "",
    settings_open: False,
    error: None,
    restoring: True,
  )
}

pub fn init() -> #(State, List(system.Effect(Message))) {
  #(new(), [load_settings()])
}

pub fn update(state: State, message: Message, origin, can_save) {
  case message {
    ToggleSettings if !state.restoring -> #(
      State(..state, settings_open: !state.settings_open),
      [],
      None,
    )
    ProviderSelected(value) if !state.restoring -> {
      let selected_provider = provider_from_string(value)
      let model_name = case selected_provider {
        Some(selected_provider) -> default_model(selected_provider)
        None -> ""
      }
      let state =
        State(
          ..state,
          provider: selected_provider,
          model_name:,
          api_key: "",
          error: None,
        )
      #(state, [], None)
    }
    ModelSelected(model_name) if !state.restoring -> #(
      State(..state, model_name:, error: None),
      [],
      None,
    )
    ApiKeyUpdated(api_key) if !state.restoring -> #(
      State(..state, api_key:, error: None),
      [],
      None,
    )
    SaveSettings if !state.restoring -> save(state, origin, can_save)
    SessionSettingsLoaded(provider, model_name, api_key) if state.restoring ->
      restore(state, provider, model_name, api_key, origin)
    SessionSettingsStored -> #(state, [], None)
    _ -> #(state, [], None)
  }
}

pub fn require_configuration(state: State) {
  State(
    ..state,
    settings_open: True,
    error: Some("Set an LLM provider before sending a message."),
  )
}

fn restore(state, stored_provider, stored_model, stored_api_key, origin) {
  let selected_provider = provider_from_string(stored_provider)
  let model_name = string.trim(stored_model)
  let api_key = string.trim(stored_api_key)
  case valid(selected_provider, model_name, api_key), selected_provider {
    True, Some(selected_provider) -> {
      let llm = make_llm(selected_provider, model_name, api_key, origin)
      let state =
        State(
          provider: Some(selected_provider),
          model_name:,
          api_key:,
          configured: True,
          active_provider: Some(selected_provider),
          active_model: model_name,
          settings_open: False,
          error: None,
          restoring: False,
        )
      #(state, [], Some(llm))
    }
    _, _ -> {
      let state =
        State(
          ..state,
          provider: selected_provider,
          model_name:,
          api_key:,
          configured: False,
          settings_open: True,
          error: None,
          restoring: False,
        )
      #(state, [], None)
    }
  }
}

fn save(state: State, origin, can_save) {
  let model_name = string.trim(state.model_name)
  let api_key = string.trim(state.api_key)
  case can_save, state.provider, model_name, api_key {
    True, Some(selected_provider), model_name, api_key
      if model_name != "" && api_key != ""
    -> {
      let llm = make_llm(selected_provider, model_name, api_key, origin)
      let state =
        State(
          ..state,
          model_name:,
          api_key:,
          configured: True,
          active_provider: Some(selected_provider),
          active_model: model_name,
          settings_open: False,
          error: None,
        )
      #(
        state,
        [store_settings(provider_id(selected_provider), model_name, api_key)],
        Some(llm),
      )
    }
    True, _, _, _ -> #(
      State(..state, error: Some("Choose a provider, model, and API token.")),
      [],
      None,
    )
    False, _, _, _ -> #(
      State(..state, error: Some("Wait for the current response to finish.")),
      [],
      None,
    )
  }
}

fn load_settings() {
  use provider <- system.GetSessionStorageItem(provider_key)
  use model <- system.GetSessionStorageItem(model_key)
  use api_key <- system.GetSessionStorageItem(api_key_key)
  system.Done(SessionSettingsLoaded(
    stored_value(provider),
    stored_value(model),
    stored_value(api_key),
  ))
}

fn stored_value(value) {
  case value {
    Ok(Some(value)) -> value
    _ -> ""
  }
}

fn store_settings(provider, model, api_key) {
  use _ <- system.SetSessionStorageItem(provider_key, provider)
  use _ <- system.SetSessionStorageItem(model_key, model)
  use _ <- system.SetSessionStorageItem(api_key_key, api_key)
  system.Done(SessionSettingsStored)
}

fn valid(selected_provider, model_name, api_key) {
  case selected_provider, model_name, api_key {
    Some(_), model_name, api_key if model_name != "" && api_key != "" -> True
    _, _, _ -> False
  }
}

fn make_llm(selected_provider, model_name, api_key, origin) {
  let llm_provider = case selected_provider {
    Ollama -> ollama.make_provider(api_key, origin)
    Mistral -> mistral.make_provider(api_key)
  }
  provider.Llm(provider: llm_provider, model: model_name)
}

pub fn provider_from_string(value) -> Option(ProviderChoice) {
  case value {
    "ollama" -> Some(Ollama)
    "mistral" -> Some(Mistral)
    _ -> None
  }
}

pub fn provider_id(selected_provider) {
  case selected_provider {
    Ollama -> ollama.id
    Mistral -> mistral.id
  }
}

pub fn provider_label(selected_provider) {
  case selected_provider {
    Ollama -> ollama.label
    Mistral -> mistral.label
  }
}

pub fn default_model(selected_provider) {
  case selected_provider {
    Ollama -> ollama.default_model()
    Mistral -> mistral.default_model()
  }
}

pub fn model_options(selected_provider) {
  case selected_provider {
    Ollama -> ollama.models()
    Mistral -> mistral.models()
  }
}

pub fn token_url(selected_provider) {
  case selected_provider {
    Ollama -> ollama.token_url
    Mistral -> mistral.token_url
  }
}

pub fn active_label(state: State) {
  case state.restoring, state.configured, state.active_provider {
    True, _, _ -> "Loading LLM"
    False, False, _ -> "Set up LLM"
    False, True, Some(selected_provider) ->
      provider_label(selected_provider) <> " · " <> state.active_model
    _, _, _ -> "Set up LLM"
  }
}
