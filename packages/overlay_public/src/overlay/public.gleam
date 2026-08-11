import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import lustre
import lustre/effect
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/ollama
import overlay/public/view
import overlay/web/state
import pal/system

pub fn main() -> Nil {
  let app = lustre.application(do_init, do_update, view.render)
  let assert Ok(origin) = origin.from_string(browser_origin())
  let ollama_config = case ollama_api_key() {
    "" -> ollama.Config(origin:, api_key: None)
    api_key ->
      case is_development() {
        True -> ollama.Config(origin:, api_key: Some(api_key))

        False -> ollama.cloud(api_key)
      }
  }
  let config = state.Config(provider: provider.Ollama(ollama_config), origin:)
  let assert Ok(_runtime) = lustre.start(app, "#app", config)
  Nil
}

@external(javascript, "./public_ffi.mjs", "ollamaApiKey")
fn ollama_api_key() -> String

@external(javascript, "./public_ffi.mjs", "isDevelopment")
fn is_development() -> Bool

@external(javascript, "./public_ffi.mjs", "browserOrigin")
fn browser_origin() -> String

fn do_init(config) {
  let #(state, actions) = state.init(config)
  #(state, effect.batch(list.map(actions, effect)))
}

fn do_update(state, message) {
  let #(state, actions) = state.update(state, message)
  #(state, effect.batch(list.map(actions, effect)))
}

fn effect(action) {
  effect.from(fn(dispatch) {
    promise.map(system.run(action), dispatch)
    Nil
  })
}
