import plinth/browser/location
import plinth/browser/window
import spotless/origin

pub type Config {
  Config(origin: origin.Origin)
}

pub fn load() {
  case origin.from_string(location.origin(window.location(window.self()))) {
    Ok(origin) -> Config(origin)

    _ -> panic as "No apps configured"
  }
}
