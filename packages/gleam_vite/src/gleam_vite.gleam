//// Thin bindings to Vite plugins, configuration and development-server APIs.

pub type Config

pub type Plugin

pub type Server

@external(javascript, "./vite_ffi.mjs", "configure")
pub fn configure(json: String, plugins: List(Plugin)) -> Config

@external(javascript, "./vite_ffi.mjs", "gleam")
pub fn gleam() -> Plugin

@external(javascript, "./vite_ffi.mjs", "plugin")
pub fn plugin(
  name: String,
  configure: fn(Server) -> Nil,
  changed: fn(String, Server) -> Bool,
) -> Plugin

@external(javascript, "./vite_ffi.mjs", "watch")
pub fn watch(server: Server, paths: List(String)) -> Nil

@external(javascript, "./vite_ffi.mjs", "reload")
pub fn reload(server: Server) -> Nil
