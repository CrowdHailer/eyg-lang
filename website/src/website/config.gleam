import gleam/http
import gleam/option.{None}
import plinth/browser/window
import spotless/origin

pub type Config {
  Config(registry_origin: origin.Origin)
}

pub fn load() {
  case window.origin() {
    "http://localhost:8080" ->
      Config(origin.Origin(http.Https, "localhost", None))
    "https://eyg.run" -> Config(origin.Origin(http.Https, "eyg.run", None))
    _ -> panic as "No apps configured"
  }
}
