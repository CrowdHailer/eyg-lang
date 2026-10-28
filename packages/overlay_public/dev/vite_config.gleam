//// Overlay's Vite configuration and dependency reload policy are written in Gleam.

import gleam/json
import gleam/list
import gleam/string
import gleam_vite as vite
import plinthx/node/path
import plinthx/node/process

pub fn config() {
  let assert Ok(process) = process.get()
  let environment = process.env(process)
  let hub = env(environment, "EYG_HUB", "https://eyg.run")
  let ollama = env(environment, "EYG_OLLAMA", "https://ollama.com")
  let proxies = [
    #("/api", ollama),
    #("/guides", "https://eyg.run"),
    #("/modules", hub),
    #("/artifacts", hub),
    #("/artifact/", hub),
    #("/packages", hub),
  ]
  let configuration =
    json.object([
      #("base", json.string("/overlay/")),
      #(
        "server",
        json.object([
          #("host", json.string("0.0.0.0")),
          #("port", json.int(5173)),
          #(
            "proxy",
            json.object(
              list.map(proxies, fn(proxy) {
                #(
                  proxy.0,
                  json.object([
                    #("target", json.string(proxy.1)),
                    #("changeOrigin", json.bool(True)),
                  ]),
                )
              }),
            ),
          ),
          #("watch", json.object([#("usePolling", json.bool(True))])),
        ]),
      ),
    ])
  vite.configure(json.to_string(configuration), [
    vite.gleam(),
    watch_dependencies(),
  ])
}

fn env(values, key, fallback) {
  case list.key_find(values, key) {
    Ok(value) -> value
    Error(_) -> fallback
  }
}

fn watch_dependencies() {
  let roots =
    list.map(
      ["../overlay_web", "../overlay", "../overlay_llm", "../pal"],
      fn(root) { path.resolve([root, "src"]) },
    )
  vite.plugin(
    "watch-gleam-dependencies",
    fn(server) { vite.watch(server, roots) },
    fn(file, server) {
      let changed =
        string.ends_with(file, ".gleam")
        && list.any(roots, fn(root) { string.starts_with(file, root <> "/") })
      case changed {
        True -> vite.reload(server)
        False -> Nil
      }
      changed
    },
  )
}
