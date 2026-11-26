import envoy
import gleam/result.{try}

pub type Config {
  Config(secret_key_base: String, postgres: Postgres)
}

pub type Postgres {
  Postgres(host: String, password: String)
}

pub fn from_env() {
  use secret_key_base <- try(envoy.get("SECRET_KEY_BASE"))
  use postgres_host <- try(envoy.get("POSTGRES_HOST"))
  use postgres_password <- try(envoy.get("POSTGRES_PASSWORD"))
  let postgres = Postgres(host: postgres_host, password: postgres_password)
  Ok(Config(secret_key_base:, postgres:))
}
