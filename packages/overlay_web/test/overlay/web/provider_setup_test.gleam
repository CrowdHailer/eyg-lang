import gleam/option.{None, Some}
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/mistral
import overlay/llm/provider/ollama
import overlay/web/provider_setup
import pal/system

pub fn starts_by_loading_session_settings_test() {
  let #(state, actions) = provider_setup.init()

  assert False == state.configured
  assert True == state.restoring
  assert False == state.settings_open
  let assert [system.GetSessionStorageItem("overlay.llm.provider", _)] = actions
}

pub fn missing_session_settings_open_setup_test() {
  let #(state, actions) = provider_setup.init()
  let assert [load] = actions
  let message = finish_loading(load, Error("unavailable"), Ok(None), Ok(None))
  let #(state, actions, llm) =
    provider_setup.update(state, message, test_origin(), True)

  assert [] == actions
  assert None == llm
  assert False == state.restoring
  assert False == state.configured
  assert True == state.settings_open
}

pub fn restores_ollama_session_test() {
  let state = provider_setup.new()
  let #(state, actions, llm) =
    provider_setup.update(
      state,
      provider_setup.SessionSettingsLoaded(
        "ollama",
        "qwen3.5:397b",
        "ollama-key",
      ),
      test_origin(),
      True,
    )

  let assert Some(provider.Llm(
    provider.Ollama(ollama.Config(origin: selected_origin, api_key: Some(key))),
    "qwen3.5:397b",
  )) = llm
  assert [] == actions
  assert test_origin() == selected_origin
  assert "ollama-key" == key
  assert True == state.configured
  assert False == state.settings_open
}

pub fn restores_mistral_session_test() {
  let state = provider_setup.new()
  let #(state, _, llm) =
    provider_setup.update(
      state,
      provider_setup.SessionSettingsLoaded(
        "mistral",
        "mistral-small-latest",
        "mistral-key",
      ),
      test_origin(),
      True,
    )

  let assert Some(provider.Llm(
    provider.Mistral(mistral.Config(api_key: "mistral-key")),
    "mistral-small-latest",
  )) = llm
  assert True == state.configured
}

pub fn saves_provider_settings_to_session_test() {
  let state = ready()
  let #(state, _, _) =
    provider_setup.update(
      state,
      provider_setup.ProviderSelected("mistral"),
      test_origin(),
      True,
    )
  let #(state, _, _) =
    provider_setup.update(
      state,
      provider_setup.ApiKeyUpdated("mistral-key"),
      test_origin(),
      True,
    )
  let #(state, actions, llm) =
    provider_setup.update(
      state,
      provider_setup.SaveSettings,
      test_origin(),
      True,
    )

  let assert Some(provider.Llm(
    provider.Mistral(mistral.Config(api_key: "mistral-key")),
    "mistral-small-latest",
  )) = llm
  assert True == state.configured
  assert False == state.settings_open
  let assert [store] = actions
  assert provider_setup.SessionSettingsStored == finish_storing(store)
}

pub fn provider_selection_resets_model_and_token_test() {
  let state = provider_setup.State(..ready(), api_key: "old-key")
  let #(state, _, _) =
    provider_setup.update(
      state,
      provider_setup.ProviderSelected("ollama"),
      test_origin(),
      True,
    )

  assert Some(provider_setup.Ollama) == state.provider
  assert "qwen3.5:397b" == state.model_name
  assert "" == state.api_key
}

pub fn duplicate_session_restore_is_ignored_test() {
  let state = ready()
  let #(unchanged, actions, llm) =
    provider_setup.update(
      state,
      provider_setup.SessionSettingsLoaded(
        "mistral",
        "mistral-small-latest",
        "old-key",
      ),
      test_origin(),
      True,
    )

  assert state == unchanged
  assert [] == actions
  assert None == llm
}

fn ready() {
  let state = provider_setup.new()
  let #(state, _, _) =
    provider_setup.update(
      state,
      provider_setup.SessionSettingsLoaded("", "", ""),
      test_origin(),
      True,
    )
  state
}

fn test_origin() {
  origin.https("eyg.test")
}

fn finish_loading(effect, provider, model, api_key) {
  let assert system.GetSessionStorageItem("overlay.llm.provider", resume) =
    effect
  let assert system.GetSessionStorageItem("overlay.llm.model", resume) =
    resume(provider)
  let assert system.GetSessionStorageItem("overlay.llm.api_key", resume) =
    resume(model)
  let assert system.Done(message) = resume(api_key)
  message
}

fn finish_storing(effect) {
  let assert system.SetSessionStorageItem(
    "overlay.llm.provider",
    "mistral",
    resume,
  ) = effect
  let assert system.SetSessionStorageItem(
    "overlay.llm.model",
    "mistral-small-latest",
    resume,
  ) = resume(Ok(Nil))
  let assert system.SetSessionStorageItem(
    "overlay.llm.api_key",
    "mistral-key",
    resume,
  ) = resume(Ok(Nil))
  let assert system.Done(message) = resume(Ok(Nil))
  message
}
