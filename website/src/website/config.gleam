import plinth/browser/window
import spotless/origin

pub type Config {
  Config(origin: origin.Origin)
}

pub fn load() {
  case origin.from_string(window.origin()) {
    Ok(origin) -> Config(origin)

    _ -> panic as "No apps configured"
  }
}
