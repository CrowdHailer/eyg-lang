import gleam/http
import gleam/option.{None, Some}
import plinth/browser/window
import spotless/origin

pub type Config {
  Config(registry_origin: origin.Origin)
}

pub fn load() {
  case window.origin() {
    "https://localhost:8001" ->
      Config(origin.Origin(http.Https, "localhost", Some(8001)))
    "https://localhost" -> Config(origin.Origin(http.Https, "localhost", None))
    "https://eyg.run" -> Config(origin.Origin(http.Https, "eyg.run", None))
    _ -> panic as "No apps configured"
  }
}
