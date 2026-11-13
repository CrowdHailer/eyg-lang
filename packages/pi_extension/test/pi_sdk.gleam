//// Bindings to official SDK constructors and the SDK's faux provider.

import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}

@external(javascript, "./pi_sdk_ffi.mjs", "modelRuntime")
pub fn model_runtime(options: Dynamic) -> Promise(Dynamic)

@external(javascript, "./pi_sdk_ffi.mjs", "resourceLoader")
pub fn resource_loader(options: Dynamic) -> Dynamic

@external(javascript, "./pi_sdk_ffi.mjs", "sessionManager")
pub fn session_manager() -> Dynamic

@external(javascript, "./pi_sdk_ffi.mjs", "settingsManager")
pub fn settings_manager(options: Dynamic) -> Dynamic

@external(javascript, "./pi_sdk_ffi.mjs", "session")
pub fn session(options: Dynamic) -> Promise(Dynamic)

@external(javascript, "./pi_sdk_ffi.mjs", "faux")
pub fn faux(options: Dynamic) -> Dynamic

@external(javascript, "./pi_sdk_ffi.mjs", "assistant")
pub fn assistant(content: Dynamic, options: Dynamic) -> Dynamic

@external(javascript, "./pi_sdk_ffi.mjs", "toolCall")
pub fn tool_call(name: String, arguments: Dynamic) -> Dynamic

@external(javascript, "./pi_sdk_ffi.mjs", "currentTools")
pub fn current_tools(context: Dynamic) -> Dynamic
