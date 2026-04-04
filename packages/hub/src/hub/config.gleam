import envoy
import gleam/result.{try}

pub type Config {
  Config(secret_key_base: String, postgres_password: String)
}

pub fn from_env() {
  use secret_key_base <- try(envoy.get("SECRET_KEY_BASE"))
  use postgres_password <- try(envoy.get("POSTGRES_PASSWORD"))
  Ok(Config(secret_key_base:, postgres_password:))
}
