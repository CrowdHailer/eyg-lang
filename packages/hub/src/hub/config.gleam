import envoy
import gleam/result.{try}

pub type Config {
  Config(secret_key_base: String)
}

pub fn from_env() {
  use secret_key_base <- try(envoy.get("SECRET_KEY_BASE"))
  Ok(Config(secret_key_base:))
}
